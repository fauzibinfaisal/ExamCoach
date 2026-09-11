import 'package:exam_coach/analytics/analytics_events.dart';
import 'package:exam_coach/features/auth/domain/user_identity.dart';
import 'package:exam_coach/features/subscription/application/subscription_state.dart';
import 'package:exam_coach/features/subscription/domain/subscription_models.dart';
import 'package:exam_coach/features/subscription/domain/subscription_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class SubscriptionCubit extends Cubit<SubscriptionState> {
  factory SubscriptionCubit({
    required SubscriptionRepository repository,
    required UserIdentity userIdentity,
    required AnalyticsTracker analytics,
  }) => SubscriptionCubit._(repository, userIdentity, analytics);

  SubscriptionCubit._(this._repository, this._userIdentity, this._analytics)
    : super(const SubscriptionState());

  final SubscriptionRepository _repository;
  final UserIdentity _userIdentity;
  final AnalyticsTracker _analytics;
  int _epoch = 0;
  bool _paywallTracked = false;

  Future<void> refresh() async {
    final epoch = ++_epoch;
    if (!_repository.isAvailable) {
      emit(
        SubscriptionState(
          status: SubscriptionViewStatus.unavailable,
          message: _repository.unavailableReason,
        ),
      );
      return;
    }
    if (!_userIdentity.isAuthenticated) {
      emit(
        const SubscriptionState(
          status: SubscriptionViewStatus.signedOut,
          message: 'Masuk ke akun untuk melihat dan membeli paket.',
        ),
      );
      return;
    }
    emit(
      SubscriptionState(
        status: SubscriptionViewStatus.loading,
        entitlement: state.entitlement,
        packages: state.packages,
      ),
    );
    try {
      final snapshot = await _repository.load();
      if (epoch != _epoch) return;
      emit(
        SubscriptionState(
          status: SubscriptionViewStatus.ready,
          entitlement: snapshot.entitlement,
          packages: snapshot.packages,
          message: snapshot.packages.isEmpty
              ? 'Belum ada offering aktif di RevenueCat.'
              : null,
        ),
      );
    } on SubscriptionFailure catch (error) {
      if (epoch == _epoch) emit(_failure(error));
    } on Object catch (error) {
      if (epoch == _epoch) {
        emit(
          SubscriptionState(
            status: SubscriptionViewStatus.failure,
            message: 'Paket gagal dimuat: $error',
          ),
        );
      }
    }
  }

  Future<void> purchase(String packageId) async {
    if (state.status == SubscriptionViewStatus.loading) return;
    final epoch = ++_epoch;
    emit(_loading());
    await _trackSafely(
      AnalyticsEvents.purchaseStarted,
      properties: {'packageId': packageId},
    );
    try {
      final snapshot = await _repository.purchase(packageId);
      if (epoch != _epoch) return;
      await _trackSafely(
        AnalyticsEvents.subscriptionStarted,
        properties: {
          'packageId': packageId,
          'planId': snapshot.entitlement.planId,
        },
      );
      if (epoch != _epoch) return;
      emit(_success(snapshot, 'Pembelian terverifikasi oleh server.'));
    } on SubscriptionFailure catch (error) {
      if (epoch == _epoch) emit(_failure(error));
    } on Object catch (error) {
      if (epoch == _epoch) {
        emit(_genericFailure('Pembelian gagal: $error'));
      }
    }
  }

  Future<void> restore() async {
    if (state.status == SubscriptionViewStatus.loading) return;
    final epoch = ++_epoch;
    emit(_loading());
    await _trackSafely(AnalyticsEvents.restorePurchase);
    try {
      final snapshot = await _repository.restore();
      if (epoch != _epoch) return;
      emit(_success(snapshot, 'Status pembelian selesai dipulihkan.'));
    } on SubscriptionFailure catch (error) {
      if (epoch == _epoch) emit(_failure(error));
    } on Object catch (error) {
      if (epoch == _epoch) {
        emit(_genericFailure('Pemulihan pembelian gagal: $error'));
      }
    }
  }

  Future<void> recordPaywallViewed() async {
    if (_paywallTracked) return;
    _paywallTracked = true;
    await _trackSafely(AnalyticsEvents.paywallViewed);
  }

  SubscriptionState _loading() => SubscriptionState(
    status: SubscriptionViewStatus.loading,
    entitlement: state.entitlement,
    packages: state.packages,
  );

  SubscriptionState _success(SubscriptionSnapshot snapshot, String message) =>
      SubscriptionState(
        status: SubscriptionViewStatus.success,
        entitlement: snapshot.entitlement,
        packages: snapshot.packages,
        message: message,
      );

  SubscriptionState _failure(SubscriptionFailure error) {
    final status = switch (error.code) {
      SubscriptionFailureCode.authenticationRequired =>
        SubscriptionViewStatus.signedOut,
      SubscriptionFailureCode.unavailable => SubscriptionViewStatus.unavailable,
      SubscriptionFailureCode.cancelled => SubscriptionViewStatus.cancelled,
      SubscriptionFailureCode.store ||
      SubscriptionFailureCode.verification => SubscriptionViewStatus.failure,
    };
    return SubscriptionState(
      status: status,
      entitlement: state.entitlement,
      packages: state.packages,
      message: error.message,
    );
  }

  SubscriptionState _genericFailure(String message) => SubscriptionState(
    status: SubscriptionViewStatus.failure,
    entitlement: state.entitlement,
    packages: state.packages,
    message: message,
  );

  Future<void> _trackSafely(
    String event, {
    Map<String, Object> properties = const {},
  }) async {
    try {
      await _analytics.track(event, properties: properties);
    } on Object {
      // Analytics must not block store or entitlement handling.
    }
  }

  @override
  Future<void> close() {
    _epoch++;
    return super.close();
  }
}
