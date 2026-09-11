import 'package:exam_coach/analytics/analytics_events.dart';
import 'package:exam_coach/features/ai_coach/application/ai_coach_context_builder.dart';
import 'package:exam_coach/features/ai_coach/application/ai_coach_state.dart';
import 'package:exam_coach/features/ai_coach/domain/ai_coach_cache_store.dart';
import 'package:exam_coach/features/ai_coach/domain/ai_coach_models.dart';
import 'package:exam_coach/features/ai_coach/domain/ai_coach_repository.dart';
import 'package:exam_coach/features/auth/domain/user_identity.dart';
import 'package:exam_coach/features/learning/application/learning_flow_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

typedef AiCoachNow = DateTime Function();

class AiCoachCubit extends Cubit<AiCoachState> {
  factory AiCoachCubit({
    required AiCoachContextBuilder contextBuilder,
    required AiCoachRepository repository,
    required AiCoachCacheStore cacheStore,
    required UserIdentity userIdentity,
    required AnalyticsTracker analytics,
    AiCoachNow? now,
  }) => AiCoachCubit._(
    contextBuilder,
    repository,
    cacheStore,
    userIdentity,
    analytics,
    now ?? (() => DateTime.now().toUtc()),
  );

  AiCoachCubit._(
    this._contextBuilder,
    this._repository,
    this._cacheStore,
    this._userIdentity,
    this._analytics,
    this._now,
  ) : super(const AiCoachState());

  final AiCoachContextBuilder _contextBuilder;
  final AiCoachRepository _repository;
  final AiCoachCacheStore _cacheStore;
  final UserIdentity _userIdentity;
  final AnalyticsTracker _analytics;
  final AiCoachNow _now;

  int _epoch = 0;
  String? _viewedInsightKey;

  Future<void> refresh(LearningFlowState learningState) async {
    final epoch = ++_epoch;
    final context = _contextBuilder.build(learningState);
    if (context == null) {
      emit(
        const AiCoachState(
          status: AiCoachStatus.noLearningData,
          message: 'Selesaikan tryout terlebih dahulu untuk membuat insight.',
        ),
      );
      return;
    }

    AiCoachInsight? cached;
    try {
      cached = await _cacheStore.load(
        userId: _userIdentity.dataOwnerId,
        contextKey: context.contextKey,
        now: _utcNow(),
      );
    } on Object {
      cached = null;
    }
    if (epoch != _epoch) return;

    if (!_repository.isAvailable) {
      emit(
        AiCoachState(
          status: AiCoachStatus.unavailable,
          context: context,
          insight: cached,
          message: cached == null
              ? 'AI Coach belum dikonfigurasi. Insight deterministik tetap tersedia.'
              : 'Menampilkan insight AI yang tersimpan di perangkat.',
        ),
      );
      return;
    }
    if (!_userIdentity.isAuthenticated) {
      emit(
        AiCoachState(
          status: AiCoachStatus.signedOut,
          context: context,
          insight: cached,
          message: cached == null
              ? 'Masuk ke akun untuk meminta insight AI.'
              : 'Anda sedang keluar akun; insight tersimpan tetap dapat dibaca.',
        ),
      );
      return;
    }

    emit(
      AiCoachState(
        status: AiCoachStatus.loading,
        context: context,
        insight: cached,
        message: 'Memeriksa entitlement dan kuota…',
      ),
    );
    try {
      final quota = await _repository.getStatus();
      if (epoch != _epoch) return;
      if (!quota.enabled) {
        emit(
          AiCoachState(
            status: AiCoachStatus.unavailable,
            context: context,
            quota: quota,
            insight: cached,
            message: 'AI Coach dinonaktifkan oleh kebijakan server.',
          ),
        );
      } else if (!quota.canGenerate) {
        emit(
          AiCoachState(
            status: AiCoachStatus.quotaExhausted,
            context: context,
            quota: quota,
            insight: cached,
            message: 'Kuota AI Coach hari ini sudah habis.',
          ),
        );
      } else if (cached != null) {
        emit(
          AiCoachState(
            status: AiCoachStatus.success,
            context: context,
            quota: quota,
            insight: cached,
            message: 'Insight tersimpan tersedia untuk hasil terbaru.',
          ),
        );
      } else {
        emit(
          AiCoachState(
            status: AiCoachStatus.ready,
            context: context,
            quota: quota,
          ),
        );
      }
    } on AiCoachFailure catch (error) {
      if (epoch != _epoch) return;
      emit(_failureState(context, cached, error));
    } on Object catch (error) {
      if (epoch != _epoch) return;
      emit(
        AiCoachState(
          status: AiCoachStatus.failure,
          context: context,
          insight: cached,
          message: 'Status AI Coach gagal dimuat: $error',
        ),
      );
    }
  }

  Future<void> generate() async {
    final context = state.context;
    if (context == null ||
        !_repository.isAvailable ||
        !_userIdentity.isAuthenticated ||
        state.status == AiCoachStatus.loading) {
      return;
    }
    final epoch = ++_epoch;
    emit(
      AiCoachState(
        status: AiCoachStatus.loading,
        context: context,
        quota: state.quota,
        insight: state.insight,
        message: 'AI Coach sedang menyusun panduan singkat…',
      ),
    );
    await _trackSafely(
      AnalyticsEvents.aiInsightRequested,
      properties: {'sessionId': context.sourceSessionId},
    );

    try {
      final result = await _repository.generate(context);
      if (epoch != _epoch) return;
      await _saveSafely(
        userId: _userIdentity.dataOwnerId,
        sourceSessionId: context.sourceSessionId,
        insight: result.insight,
      );
      await _trackSafely(
        AnalyticsEvents.aiInsightGenerated,
        properties: {
          'sessionId': context.sourceSessionId,
          'provider': result.insight.provider,
          'model': result.insight.model,
          'serverCache': result.insight.fromServerCache,
        },
      );
      if (epoch != _epoch) return;
      emit(
        AiCoachState(
          status: AiCoachStatus.success,
          context: context,
          quota: result.quota,
          insight: result.insight,
          message: result.insight.fromServerCache
              ? 'Insight yang sama diambil dari cache aman.'
              : 'Insight AI baru berhasil dibuat.',
        ),
      );
    } on AiCoachFailure catch (error) {
      if (epoch != _epoch) return;
      if (error.code == AiCoachFailureCode.quotaExhausted) {
        await _trackSafely(
          AnalyticsEvents.aiQuotaExhausted,
          properties: {'sessionId': context.sourceSessionId},
        );
      }
      emit(_failureState(context, state.insight, error));
    } on Object catch (error) {
      if (epoch != _epoch) return;
      emit(
        AiCoachState(
          status: AiCoachStatus.failure,
          context: context,
          quota: state.quota,
          insight: state.insight,
          message: 'Insight AI tidak dapat dibuat: $error',
        ),
      );
    }
  }

  Future<void> recordViewed() async {
    final insight = state.insight;
    final context = state.context;
    if (insight == null || context == null) return;
    final key =
        '${insight.contextKey}:${insight.generatedAt.toIso8601String()}';
    if (_viewedInsightKey == key) return;
    _viewedInsightKey = key;
    await _trackSafely(
      AnalyticsEvents.aiInsightViewed,
      properties: {
        'sessionId': context.sourceSessionId,
        'provider': insight.provider,
      },
    );
  }

  AiCoachState _failureState(
    AiCoachContext context,
    AiCoachInsight? cached,
    AiCoachFailure error,
  ) {
    final status = switch (error.code) {
      AiCoachFailureCode.authenticationRequired => AiCoachStatus.signedOut,
      AiCoachFailureCode.quotaExhausted => AiCoachStatus.quotaExhausted,
      AiCoachFailureCode.unavailable => AiCoachStatus.unavailable,
      AiCoachFailureCode.invalidResponse ||
      AiCoachFailureCode.transport => AiCoachStatus.failure,
    };
    return AiCoachState(
      status: status,
      context: context,
      quota: error.quota ?? state.quota,
      insight: cached,
      message: error.message,
    );
  }

  Future<void> _trackSafely(
    String event, {
    Map<String, Object> properties = const {},
  }) async {
    try {
      await _analytics.track(event, properties: properties);
    } on Object {
      // Analytics must never block coaching or deterministic learning.
    }
  }

  Future<void> _saveSafely({
    required String userId,
    required String sourceSessionId,
    required AiCoachInsight insight,
  }) async {
    try {
      await _cacheStore.save(
        userId: userId,
        sourceSessionId: sourceSessionId,
        insight: insight,
      );
    } on Object {
      // A local cache failure must not hide a valid, already-quota-charged
      // server response. The insight stays available for the current session.
    }
  }

  DateTime _utcNow() {
    final value = _now();
    return value.isUtc ? value : value.toUtc();
  }

  @override
  Future<void> close() {
    _epoch++;
    return super.close();
  }
}
