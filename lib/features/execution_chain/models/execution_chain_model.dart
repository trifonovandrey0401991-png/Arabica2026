/// Шаг цепочки выполнений
class ExecutionChainStep {
  final String id;        // "attendance", "shift", etc.
  final String name;      // "Я на работе"
  final int order;
  final bool completed;   // только в status response

  ExecutionChainStep({
    required this.id,
    required this.name,
    required this.order,
    this.completed = false,
  });

  factory ExecutionChainStep.fromJson(Map<String, dynamic> json) {
    return ExecutionChainStep(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      order: json['order'] ?? 0,
      completed: json['completed'] ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'order': order,
  };
}

/// Конфиг цепочки (настраивается админом)
class ExecutionChainConfig {
  final bool enabled;
  final List<ExecutionChainStep> steps;
  final List<AvailableModule> availableModules;

  ExecutionChainConfig({
    required this.enabled,
    required this.steps,
    this.availableModules = const [],
  });

  factory ExecutionChainConfig.fromJson(Map<String, dynamic> json) {
    return ExecutionChainConfig(
      enabled: json['enabled'] ?? false,
      steps: (json['steps'] as List<dynamic>? ?? [])
          .map((s) => ExecutionChainStep.fromJson(s as Map<String, dynamic>))
          .toList(),
      availableModules: (json['availableModules'] as List<dynamic>? ?? [])
          .map((m) => AvailableModule.fromJson(m as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Статус цепочки для конкретного сотрудника
class ExecutionChainStatus {
  final bool enabled;
  final List<ExecutionChainStep> steps;

  ExecutionChainStatus({
    required this.enabled,
    required this.steps,
  });

  factory ExecutionChainStatus.fromJson(Map<String, dynamic> json) {
    return ExecutionChainStatus(
      enabled: json['enabled'] ?? false,
      steps: (json['steps'] as List<dynamic>? ?? [])
          .map((s) => ExecutionChainStep.fromJson(s as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Можно ли выполнить действие с данным id
  bool canExecute(String stepId) {
    if (!enabled || steps.isEmpty) return true;

    // Если шаг не в цепочке — он доступен без ограничений
    final stepIndex = steps.indexWhere((s) => s.id == stepId);
    if (stepIndex == -1) return true;

    // Все предыдущие шаги должны быть выполнены
    for (int i = 0; i < stepIndex; i++) {
      if (!steps[i].completed) return false;
    }
    return true;
  }

  /// Какой шаг блокирует выполнение (первый невыполненный до целевого)
  ExecutionChainStep? getBlockingStep(String stepId) {
    if (!enabled || steps.isEmpty) return null;

    final stepIndex = steps.indexWhere((s) => s.id == stepId);
    if (stepIndex == -1) return null;

    for (int i = 0; i < stepIndex; i++) {
      if (!steps[i].completed) return steps[i];
    }
    return null;
  }
}

/// Доступный модуль для добавления в цепочку
class AvailableModule {
  final String id;
  final String name;

  AvailableModule({required this.id, required this.name});

  factory AvailableModule.fromJson(Map<String, dynamic> json) {
    return AvailableModule(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
    );
  }
}
