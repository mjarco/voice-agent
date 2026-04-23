class ModelCost {
  const ModelCost({
    required this.model,
    required this.costUsd,
  });

  final String model;
  final double costUsd;

  factory ModelCost.fromMap(Map<String, dynamic> map) {
    return ModelCost(
      model: map['model'] as String,
      costUsd: (map['cost_usd'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'model': model,
      'cost_usd': costUsd,
    };
  }
}

class DailyUsage {
  const DailyUsage({
    required this.date,
    required this.costUsd,
    required this.costPln,
    required this.requests,
    required this.models,
  });

  final String date;
  final double costUsd;
  final double costPln;
  final int requests;
  final List<ModelCost> models;

  factory DailyUsage.fromMap(Map<String, dynamic> map) {
    final modelsMap = map['models'] as Map<String, dynamic>? ?? {};
    final modelsList = modelsMap.entries.map((e) {
      final value = e.value as Map<String, dynamic>;
      return ModelCost(
        model: e.key,
        costUsd: (value['cost_usd'] as num).toDouble(),
      );
    }).toList();

    return DailyUsage(
      date: map['date'] as String,
      costUsd: (map['cost_usd'] as num).toDouble(),
      costPln: (map['cost_pln'] as num).toDouble(),
      requests: map['requests'] as int,
      models: modelsList,
    );
  }

  Map<String, dynamic> toMap() {
    final modelsMap = <String, dynamic>{};
    for (final m in models) {
      modelsMap[m.model] = {'cost_usd': m.costUsd};
    }
    return {
      'date': date,
      'cost_usd': costUsd,
      'cost_pln': costPln,
      'requests': requests,
      'models': modelsMap,
    };
  }
}

class UsageSummary {
  const UsageSummary({
    required this.periodFrom,
    required this.periodTo,
    required this.totalCostUsd,
    required this.totalCostPln,
    required this.totalInputTokens,
    required this.totalOutputTokens,
    required this.totalRequests,
    required this.daily,
  });

  final String periodFrom;
  final String periodTo;
  final double totalCostUsd;
  final double totalCostPln;
  final int totalInputTokens;
  final int totalOutputTokens;
  final int totalRequests;
  final List<DailyUsage> daily;

  factory UsageSummary.fromMap(Map<String, dynamic> map) {
    final period = map['period'] as Map<String, dynamic>;
    final dailyList = (map['daily'] as List<dynamic>)
        .map((e) => DailyUsage.fromMap(e as Map<String, dynamic>))
        .toList();

    return UsageSummary(
      periodFrom: period['from'] as String,
      periodTo: period['to'] as String,
      totalCostUsd: (map['total_cost_usd'] as num).toDouble(),
      totalCostPln: (map['total_cost_pln'] as num).toDouble(),
      totalInputTokens: map['total_input_tokens'] as int,
      totalOutputTokens: map['total_output_tokens'] as int,
      totalRequests: map['total_requests'] as int,
      daily: dailyList,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'period': {
        'from': periodFrom,
        'to': periodTo,
      },
      'total_cost_usd': totalCostUsd,
      'total_cost_pln': totalCostPln,
      'total_input_tokens': totalInputTokens,
      'total_output_tokens': totalOutputTokens,
      'total_requests': totalRequests,
      'daily': daily.map((d) => d.toMap()).toList(),
    };
  }
}
