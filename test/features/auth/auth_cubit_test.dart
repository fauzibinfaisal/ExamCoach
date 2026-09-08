import 'dart:async';

import 'package:exam_coach/features/auth/application/auth_cubit.dart';
import 'package:exam_coach/features/auth/application/auth_state.dart';
import 'package:exam_coach/features/auth/domain/account_data_store.dart';
import 'package:exam_coach/features/auth/domain/auth_repository.dart';
import 'package:exam_coach/features/auth/domain/auth_user.dart';
import 'package:exam_coach/features/auth/domain/user_identity.dart';
import 'package:exam_coach/features/exam/data/mock_question_repository.dart';
import 'package:exam_coach/features/learning/application/learning_flow_cubit.dart';
import 'package:exam_coach/learning_engine/adaptive_drill_engine.dart';
import 'package:exam_coach/learning_engine/recommendation_engine.dart';
import 'package:exam_coach/learning_engine/scoring_engine.dart';
import 'package:exam_coach/learning_engine/weakness_analyzer.dart';
import 'package:exam_coach/services/sync/application/sync_coordinator.dart';
import 'package:exam_coach/services/sync/application/sync_worker.dart';
import 'package:exam_coach/services/sync/domain/connectivity_monitor.dart';
import 'package:exam_coach/services/sync/domain/remote_learning_snapshot.dart';
import 'package:exam_coach/services/sync/domain/sync_run_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('binds an authenticated user, recovers, and starts sync', () async {
    final auth = _FakeAuthRepository();
    final accounts = _FakeAccountDataStore();
    final identity = UserIdentity();
    final learning = _learningCubit(identity);
    final runner = _RecordingSyncRunner();
    final coordinator = SyncCoordinator(
      connectivityMonitor: const _OnlineConnectivityMonitor(),
      syncRunner: runner,
    );
    final cubit = AuthCubit(
      authRepository: auth,
      accountDataStore: accounts,
      userIdentity: identity,
      learningFlowCubit: learning,
      recoveryGateway: _FakeRecoveryGateway(),
      syncCoordinator: coordinator,
    );
    addTearDown(cubit.close);
    addTearDown(learning.close);
    addTearDown(auth.close);
    await cubit.start();

    auth.emit(
      const AuthUser(
        uid: 'firebase_user_123',
        email: 'user@example.com',
        emailVerified: true,
      ),
    );
    await _waitFor(() => cubit.state.status == AuthStatus.signedIn);

    expect(cubit.state.user?.uid, 'firebase_user_123');
    expect(identity.authenticatedUserId, 'firebase_user_123');
    expect(identity.dataOwnerId, 'firebase_user_123');
    expect(accounts.claims, ['firebase_user_123']);
    expect(accounts.imports, 1);
    expect(runner.runs, 1);
  });

  test(
    'forces sign-out and preserves the account-binding conflict message',
    () async {
      final auth = _FakeAuthRepository();
      final accounts = _FakeAccountDataStore(conflict: true);
      final identity = UserIdentity(boundUserId: 'existing_user');
      final learning = _learningCubit(identity);
      final coordinator = SyncCoordinator(
        connectivityMonitor: const _OnlineConnectivityMonitor(),
        syncRunner: _RecordingSyncRunner(),
      );
      final cubit = AuthCubit(
        authRepository: auth,
        accountDataStore: accounts,
        userIdentity: identity,
        learningFlowCubit: learning,
        recoveryGateway: _FakeRecoveryGateway(),
        syncCoordinator: coordinator,
      );
      addTearDown(cubit.close);
      addTearDown(learning.close);
      addTearDown(auth.close);
      await cubit.start();

      auth.emit(
        const AuthUser(
          uid: 'different_user',
          email: 'other@example.com',
          emailVerified: false,
        ),
      );
      await _waitFor(
        () => cubit.state.status == AuthStatus.signedOut && cubit.state.isError,
      );

      expect(auth.signOutCalls, 1);
      expect(cubit.state.message, contains('terikat ke akun lain'));
      expect(identity.authenticatedUserId, isNull);
      expect(identity.dataOwnerId, 'existing_user');
    },
  );
}

LearningFlowCubit _learningCubit(UserIdentity identity) => LearningFlowCubit(
  questionRepository: MockQuestionRepository(),
  scoringEngine: const ScoringEngine(),
  weaknessAnalyzer: const WeaknessAnalyzer(),
  recommendationEngine: const RecommendationEngine(),
  adaptiveDrillEngine: const AdaptiveDrillEngine(),
  userIdentity: identity,
);

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Timed out waiting for asynchronous authentication state.');
}

class _FakeAuthRepository implements AuthRepository {
  final StreamController<AuthUser?> _controller =
      StreamController<AuthUser?>.broadcast(sync: true);
  AuthUser? _currentUser;
  int signOutCalls = 0;

  @override
  Stream<AuthUser?> get authStateChanges => _controller.stream;

  @override
  AuthUser? get currentUser => _currentUser;

  @override
  bool get isAvailable => true;

  @override
  String? get unavailableReason => null;

  void emit(AuthUser? user) {
    _currentUser = user;
    _controller.add(user);
  }

  @override
  Future<void> register({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> sendPasswordResetEmail(String email) async {}

  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signOut() async {
    signOutCalls++;
    emit(null);
  }

  Future<void> close() => _controller.close();
}

class _FakeAccountDataStore implements AccountDataStore {
  _FakeAccountDataStore({this.conflict = false});

  final bool conflict;
  final List<String> claims = [];
  int imports = 0;

  @override
  Future<AccountClaimResult> claimForUser(
    String userId, {
    required DateTime claimedAt,
  }) async {
    claims.add(userId);
    if (conflict) {
      throw AccountBindingConflict(
        boundUserId: 'existing_user',
        requestedUserId: userId,
      );
    }
    return AccountClaimResult(
      userId: userId,
      newBinding: true,
      migratedSessions: 0,
      migratedAnalyticsEvents: 0,
      rewrittenOutboxOperations: 0,
    );
  }

  @override
  Future<RecoveryImportResult> importRecoverySnapshot(
    RemoteLearningSnapshot snapshot, {
    required DateTime recoveredAt,
  }) async {
    imports++;
    return const RecoveryImportResult(status: RecoveryImportStatus.emptyRemote);
  }

  @override
  Future<String?> loadBoundUserId() async => null;
}

class _FakeRecoveryGateway implements RemoteRecoveryGateway {
  @override
  Future<RemoteLearningSnapshot> pullSnapshot() async => RemoteLearningSnapshot(
    userId: 'firebase_user_123',
    remoteRevision: 0,
    sessions: const [],
    answers: const [],
  );
}

class _RecordingSyncRunner implements SyncRunner {
  int runs = 0;

  @override
  Future<SyncRunSummary> runUntilIdle() async {
    runs++;
    return const SyncRunSummary();
  }
}

class _OnlineConnectivityMonitor implements ConnectivityMonitor {
  const _OnlineConnectivityMonitor();

  @override
  Future<bool> get isOnline async => true;

  @override
  Stream<bool> get onStatusChanged => const Stream.empty();
}
