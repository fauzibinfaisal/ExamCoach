import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';

class AiCoachWeaknessContext {
  const AiCoachWeaknessContext({
    required this.taxonomyNodeId,
    required this.label,
    required this.weaknessBasisPoints,
    required this.confidenceBasisPoints,
    required this.sampleSize,
    required this.trend,
    required this.evidence,
  });

  final String taxonomyNodeId;
  final String label;
  final int weaknessBasisPoints;
  final int confidenceBasisPoints;
  final int sampleSize;
  final String trend;
  final List<String> evidence;

  Map<String, Object?> toJson() => {
    'taxonomyNodeId': taxonomyNodeId,
    'label': label,
    'weaknessBasisPoints': weaknessBasisPoints,
    'confidenceBasisPoints': confidenceBasisPoints,
    'sampleSize': sampleSize,
    'trend': trend,
    'evidence': evidence,
  };
}

class AiCoachRecommendationContext {
  const AiCoachRecommendationContext({
    required this.type,
    required this.targetTaxonomyId,
    required this.targetLabel,
    required this.reasonCode,
    required this.reason,
    required this.expectedBenefit,
    required this.estimatedMinutes,
    required this.confidenceBasisPoints,
  });

  final String type;
  final String targetTaxonomyId;
  final String targetLabel;
  final String reasonCode;
  final String reason;
  final String expectedBenefit;
  final int estimatedMinutes;
  final int confidenceBasisPoints;

  Map<String, Object?> toJson() => {
    'type': type,
    'targetTaxonomyId': targetTaxonomyId,
    'targetLabel': targetLabel,
    'reasonCode': reasonCode,
    'reason': reason,
    'expectedBenefit': expectedBenefit,
    'estimatedMinutes': estimatedMinutes,
    'confidenceBasisPoints': confidenceBasisPoints,
  };
}

class AiCoachContext {
  AiCoachContext({
    required this.sourceSessionId,
    required this.examId,
    required this.testId,
    required this.scorePercentage,
    required this.completedAt,
    required this.topWeaknesses,
    required this.recommendation,
  }) : contextKey = _fingerprint({
         'schemaVersion': 1,
         'sourceSessionId': sourceSessionId,
         'examId': examId,
         'testId': testId,
         'scorePercentage': scorePercentage,
         'completedAt': _utcIsoMilliseconds(completedAt),
         'topWeaknesses': [
           for (final weakness in topWeaknesses) weakness.toJson(),
         ],
         'recommendation': recommendation.toJson(),
       });

  static const schemaVersion = 1;

  final String sourceSessionId;
  final String examId;
  final String testId;
  final int scorePercentage;
  final DateTime completedAt;
  final List<AiCoachWeaknessContext> topWeaknesses;
  final AiCoachRecommendationContext recommendation;
  final String contextKey;

  Map<String, Object?> get contextJson => {
    'schemaVersion': schemaVersion,
    'sourceSessionId': sourceSessionId,
    'examId': examId,
    'testId': testId,
    'scorePercentage': scorePercentage,
    'completedAt': _utcIsoMilliseconds(completedAt),
    'topWeaknesses': [for (final weakness in topWeaknesses) weakness.toJson()],
    'recommendation': recommendation.toJson(),
  };

  Map<String, Object?> toRequestJson() => {
    'protocolVersion': 1,
    'contextKey': contextKey,
    'context': contextJson,
  };
}

class AiCoachStudyPlanItem {
  const AiCoachStudyPlanItem({
    required this.title,
    required this.action,
    required this.durationMinutes,
  });

  factory AiCoachStudyPlanItem.fromJson(Map<String, Object?> json) =>
      AiCoachStudyPlanItem(
        title: _string(json['title'], 'studyPlan.title'),
        action: _string(json['action'], 'studyPlan.action'),
        durationMinutes: _integer(
          json['durationMinutes'],
          'studyPlan.durationMinutes',
        ),
      );

  final String title;
  final String action;
  final int durationMinutes;

  Map<String, Object?> toJson() => {
    'title': title,
    'action': action,
    'durationMinutes': durationMinutes,
  };
}

class AiCoachInsight {
  const AiCoachInsight({
    required this.contextKey,
    required this.summary,
    required this.weaknessExplanation,
    required this.whyItMatters,
    required this.studyPlan,
    required this.motivation,
    required this.generatedAt,
    required this.expiresAt,
    required this.provider,
    required this.model,
    required this.promptVersion,
    this.fromServerCache = false,
  });

  factory AiCoachInsight.fromJson(Map<String, Object?> json) {
    final plan = _list(json['studyPlan'], 'studyPlan')
        .map(
          (item) => AiCoachStudyPlanItem.fromJson(_object(item, 'plan item')),
        )
        .toList(growable: false);
    if (plan.length > 7) {
      throw const FormatException('studyPlan cannot exceed 7 items.');
    }
    final generatedAt = _utcTime(json['generatedAt'], 'generatedAt');
    final expiresAt = _utcTime(json['expiresAt'], 'expiresAt');
    if (!expiresAt.isAfter(generatedAt)) {
      throw const FormatException('expiresAt must follow generatedAt.');
    }
    return AiCoachInsight(
      contextKey: _string(json['contextKey'], 'contextKey'),
      summary: _string(json['summary'], 'summary'),
      weaknessExplanation: _string(
        json['weaknessExplanation'],
        'weaknessExplanation',
      ),
      whyItMatters: _string(json['whyItMatters'], 'whyItMatters'),
      studyPlan: List.unmodifiable(plan),
      motivation: _string(json['motivation'], 'motivation'),
      generatedAt: generatedAt,
      expiresAt: expiresAt,
      provider: _string(json['provider'], 'provider'),
      model: _string(json['model'], 'model'),
      promptVersion: _string(json['promptVersion'], 'promptVersion'),
      fromServerCache: json['fromServerCache'] == true,
    );
  }

  final String contextKey;
  final String summary;
  final String weaknessExplanation;
  final String whyItMatters;
  final List<AiCoachStudyPlanItem> studyPlan;
  final String motivation;
  final DateTime generatedAt;
  final DateTime expiresAt;
  final String provider;
  final String model;
  final String promptVersion;
  final bool fromServerCache;

  AiCoachInsight asLocalCache() => AiCoachInsight(
    contextKey: contextKey,
    summary: summary,
    weaknessExplanation: weaknessExplanation,
    whyItMatters: whyItMatters,
    studyPlan: studyPlan,
    motivation: motivation,
    generatedAt: generatedAt,
    expiresAt: expiresAt,
    provider: provider,
    model: model,
    promptVersion: promptVersion,
    fromServerCache: true,
  );

  Map<String, Object?> toJson() => {
    'contextKey': contextKey,
    'summary': summary,
    'weaknessExplanation': weaknessExplanation,
    'whyItMatters': whyItMatters,
    'studyPlan': [for (final item in studyPlan) item.toJson()],
    'motivation': motivation,
    'generatedAt': _utc(generatedAt).toIso8601String(),
    'expiresAt': _utc(expiresAt).toIso8601String(),
    'provider': provider,
    'model': model,
    'promptVersion': promptVersion,
  };
}

class AiCoachQuotaStatus {
  const AiCoachQuotaStatus({
    required this.enabled,
    required this.policyVersion,
    required this.planId,
    required this.entitlementStatus,
    required this.dailyLimit,
    required this.used,
    required this.resetsAt,
  });

  factory AiCoachQuotaStatus.fromJson(Map<String, Object?> json) {
    final dailyLimit = _integer(json['dailyLimit'], 'dailyLimit');
    final used = _integer(json['used'], 'used');
    if (dailyLimit < 0 || used < 0 || used > dailyLimit) {
      throw const FormatException('Quota values are outside allowed bounds.');
    }
    return AiCoachQuotaStatus(
      enabled: _boolean(json['enabled'], 'enabled'),
      policyVersion: _string(json['policyVersion'], 'policyVersion'),
      planId: _string(json['planId'], 'planId'),
      entitlementStatus: _string(
        json['entitlementStatus'],
        'entitlementStatus',
      ),
      dailyLimit: dailyLimit,
      used: used,
      resetsAt: _utcTime(json['resetsAt'], 'resetsAt'),
    );
  }

  final bool enabled;
  final String policyVersion;
  final String planId;
  final String entitlementStatus;
  final int dailyLimit;
  final int used;
  final DateTime resetsAt;

  int get remaining => dailyLimit - used;

  bool get canGenerate => enabled && remaining > 0;
}

class AiCoachGenerationResult {
  const AiCoachGenerationResult({required this.insight, required this.quota});

  final AiCoachInsight insight;
  final AiCoachQuotaStatus quota;
}

String _fingerprint(Map<String, Object?> value) =>
    sha256.convert(utf8.encode(jsonEncode(_canonical(value)))).toString();

Object? _canonical(Object? value) {
  if (value is Map) {
    final sorted = SplayTreeMap<String, Object?>();
    for (final entry in value.entries) {
      sorted[entry.key.toString()] = _canonical(entry.value);
    }
    return sorted;
  }
  if (value is List) return [for (final item in value) _canonical(item)];
  return value;
}

Map<String, Object?> _object(Object? value, String path) {
  if (value is! Map) throw FormatException('$path must be an object.');
  return value.map((key, item) => MapEntry(key.toString(), item));
}

List<Object?> _list(Object? value, String path) {
  if (value is! List) throw FormatException('$path must be an array.');
  return value;
}

String _string(Object? value, String path) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$path must be a non-empty string.');
  }
  return value;
}

int _integer(Object? value, String path) {
  if (value is! int) throw FormatException('$path must be an integer.');
  return value;
}

bool _boolean(Object? value, String path) {
  if (value is! bool) throw FormatException('$path must be a boolean.');
  return value;
}

DateTime _utcTime(Object? value, String path) {
  final parsed = DateTime.tryParse(_string(value, path));
  if (parsed == null || !parsed.isUtc) {
    throw FormatException('$path must be an ISO-8601 UTC timestamp.');
  }
  return parsed;
}

DateTime _utc(DateTime value) => value.isUtc ? value : value.toUtc();

String _utcIsoMilliseconds(DateTime value) =>
    DateTime.fromMillisecondsSinceEpoch(
      value.millisecondsSinceEpoch,
      isUtc: true,
    ).toIso8601String();
