import 'dart:async';

import 'package:exam_coach/features/auth/application/auth_state.dart';
import 'package:exam_coach/features/auth/domain/account_data_store.dart';
import 'package:exam_coach/features/auth/domain/auth_repository.dart';
import 'package:exam_coach/features/auth/domain/auth_user.dart';
import 'package:exam_coach/features/auth/domain/user_identity.dart';
import 'package:exam_coach/features/learning/application/learning_flow_cubit.dart';
import 'package:exam_coach/services/sync/application/sync_coordinator.dart';
import 'package:exam_coach/services/sync/domain/remote_learning_snapshot.dart';
import 'package:exam_coach/services/sync/domain/sync_remote_gateway.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class AuthCubit extends Cubit<AuthState> {
  factory AuthCubit({
    required AuthRepository authRepository,
    required AccountDataStore accountDataStore,
    required UserIdentity userIdentity,
    required LearningFlowCubit learningFlowCubit,
    required RemoteRecoveryGateway recoveryGateway,
    required SyncCoordinator syncCoordinator,
  }) => AuthCubit._(
    authRepository,
    accountDataStore,
    userIdentity,
    learningFlowCubit,
    recoveryGateway,
    syncCoordinator,
    const AuthState.signedOut(),
  );

  factory AuthCubit.unavailable(String reason) => AuthCubit._(
    null,
    null,
    null,
    null,
    null,
    null,
    AuthState.unavailable(reason),
  );

  AuthCubit._(
    this._authRepository,
    this._accountDataStore,
    this._userIdentity,
    this._learningFlowCubit,
    this._recoveryGateway,
    this._syncCoordinator,
    AuthState initialState,
  ) : super(initialState);

  final AuthRepository? _authRepository;
  final AccountDataStore? _accountDataStore;
  final UserIdentity? _userIdentity;
  final LearningFlowCubit? _learningFlowCubit;
  final RemoteRecoveryGateway? _recoveryGateway;
  final SyncCoordinator? _syncCoordinator;

  StreamSubscription<AuthUser?>? _subscription;
  int _authEpoch = 0;
  String? _nextSignedOutMessage;
  bool _nextSignedOutIsError = false;

  Future<void> start() async {
    final repository = _authRepository;
    if (repository == null ||
        !repository.isAvailable ||
        _subscription != null) {
      return;
    }
    _subscription = repository.authStateChanges.listen(
      (user) => unawaited(_handleUser(user)),
      onError: (Object error, StackTrace stackTrace) {
        emit(
          AuthState.signedOut(
            message: 'Status autentikasi tidak dapat dibaca: $error',
            isError: true,
          ),
        );
      },
    );
  }

  Future<void> register(String email, String password) async {
    if (!_validateCredentials(email, password)) return;
    await _runAuthAction(
      () => _authRepository!.register(email: email, password: password),
    );
  }

  Future<void> signIn(String email, String password) async {
    if (!_validateCredentials(email, password)) return;
    await _runAuthAction(
      () => _authRepository!.signIn(email: email, password: password),
    );
  }

  Future<void> sendPasswordResetEmail(String email) async {
    if (!_available()) return;
    final normalized = email.trim();
    if (!normalized.contains('@')) {
      emit(
        const AuthState.signedOut(
          message: 'Masukkan email yang valid terlebih dahulu.',
          isError: true,
        ),
      );
      return;
    }
    emit(const AuthState(status: AuthStatus.processing));
    try {
      await _authRepository!.sendPasswordResetEmail(normalized);
      emit(
        const AuthState.signedOut(
          message: 'Tautan reset kata sandi sudah diminta.',
        ),
      );
    } on AuthFailure catch (error) {
      emit(AuthState.signedOut(message: error.message, isError: true));
    } on Object catch (error) {
      emit(
        AuthState.signedOut(
          message: 'Reset kata sandi gagal: $error',
          isError: true,
        ),
      );
    }
  }

  Future<void> signOut() async {
    if (!_available()) return;
    _clearPendingSignedOutMessage();
    emit(AuthState(status: AuthStatus.processing, user: state.user));
    try {
      await _authRepository!.signOut();
    } on Object catch (error) {
      emit(
        AuthState(
          status: AuthStatus.signedIn,
          user: state.user,
          message: 'Keluar akun gagal: $error',
          isError: true,
        ),
      );
    }
  }

  Future<void> _runAuthAction(Future<void> Function() action) async {
    if (!_available()) return;
    _clearPendingSignedOutMessage();
    emit(const AuthState(status: AuthStatus.processing));
    try {
      await action();
    } on AuthFailure catch (error) {
      emit(AuthState.signedOut(message: error.message, isError: true));
    } on Object catch (error) {
      emit(
        AuthState.signedOut(
          message: 'Autentikasi gagal: $error',
          isError: true,
        ),
      );
    }
  }

  bool _validateCredentials(String email, String password) {
    if (!_available()) return false;
    if (!email.trim().contains('@') || password.length < 6) {
      emit(
        const AuthState.signedOut(
          message: 'Gunakan email valid dan kata sandi minimal 6 karakter.',
          isError: true,
        ),
      );
      return false;
    }
    return true;
  }

  bool _available() => _authRepository?.isAvailable == true;

  Future<void> _handleUser(AuthUser? user) async {
    final epoch = ++_authEpoch;
    if (user == null) {
      final message = _nextSignedOutMessage;
      final isError = _nextSignedOutIsError;
      _clearPendingSignedOutMessage();
      _userIdentity?.clearAuthentication();
      await _syncCoordinator?.dispose();
      if (epoch == _authEpoch) {
        emit(AuthState.signedOut(message: message, isError: isError));
      }
      return;
    }

    emit(AuthState(status: AuthStatus.processing, user: user));
    try {
      final claim = await _accountDataStore!.claimForUser(
        user.uid,
        claimedAt: DateTime.now().toUtc(),
      );
      _userIdentity!.bindAuthenticatedUser(user.uid);
      if (claim.newBinding || claim.claimedLocalData) {
        // The claim transaction rewrites persisted local ownership. Reload the
        // in-memory session before any later answer can write the old owner
        // back into SQLite or the sync outbox.
        await _learningFlowCubit!.restore();
      }

      var message = claim.claimedLocalData
          ? 'Data lokal berhasil dihubungkan ke akun ini.'
          : 'Akun terhubung.';
      try {
        final snapshot = await _recoveryGateway!.pullSnapshot();
        final recovery = await _accountDataStore.importRecoverySnapshot(
          snapshot,
          recoveredAt: DateTime.now().toUtc(),
        );
        if (recovery.status == RecoveryImportStatus.imported) {
          await _learningFlowCubit!.restore();
          message =
              '${recovery.sessionCount} sesi dan ${recovery.answerCount} jawaban dipulihkan.';
        } else if (recovery.status == RecoveryImportStatus.skippedLocalData) {
          message =
              '$message Data lokal dipertahankan; sinkronisasi upload berjalan.';
        }
      } on SyncAuthenticationException {
        rethrow;
      } on SyncTransportException catch (error) {
        message = '$message Recovery remote ditunda: ${error.message}';
      }

      await _syncCoordinator!.start();
      if (epoch == _authEpoch) {
        emit(
          AuthState(status: AuthStatus.signedIn, user: user, message: message),
        );
      }
    } on AccountBindingConflict catch (error) {
      await _signOutAfterUnsafeBinding(user, error.toString(), epoch: epoch);
    } on Object catch (error) {
      await _signOutAfterUnsafeBinding(
        user,
        'Akun tidak dapat dihubungkan dengan aman: $error',
        epoch: epoch,
      );
    }
  }

  Future<void> _signOutAfterUnsafeBinding(
    AuthUser user,
    String message, {
    required int epoch,
  }) async {
    _userIdentity?.clearAuthentication();
    await _syncCoordinator?.dispose();
    _nextSignedOutMessage = message;
    _nextSignedOutIsError = true;
    try {
      await _authRepository?.signOut();
      if (epoch == _authEpoch) {
        emit(AuthState.signedOut(message: message, isError: true));
      }
    } on Object catch (signOutError) {
      _clearPendingSignedOutMessage();
      if (epoch == _authEpoch) {
        emit(
          AuthState(
            status: AuthStatus.signedIn,
            user: user,
            message: '$message Keluar paksa juga gagal: $signOutError',
            isError: true,
          ),
        );
      }
    }
  }

  void _clearPendingSignedOutMessage() {
    _nextSignedOutMessage = null;
    _nextSignedOutIsError = false;
  }

  @override
  Future<void> close() async {
    _authEpoch++;
    await _subscription?.cancel();
    await _syncCoordinator?.dispose();
    return super.close();
  }
}
