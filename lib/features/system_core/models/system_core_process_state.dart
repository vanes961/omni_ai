enum SystemCoreProcessStatus {
  ready,
  starting,
  running,
  completed,
  failed,
  cancelled,
}

enum SystemCoreLogLevel { neutral, success, accent, error }

class SystemCoreLogEntry {
  const SystemCoreLogEntry({
    required this.timestamp,
    required this.message,
    required this.level,
  });

  final DateTime timestamp;
  final String message;
  final SystemCoreLogLevel level;
}

class SystemCoreProcessState {
  SystemCoreProcessState({
    required this.status,
    required Iterable<SystemCoreLogEntry> logEntries,
    this.errorMessage,
  }) : logEntries = List.unmodifiable(logEntries);

  final SystemCoreProcessStatus status;
  final List<SystemCoreLogEntry> logEntries;
  final String? errorMessage;

  bool get isActive =>
      status == SystemCoreProcessStatus.starting ||
      status == SystemCoreProcessStatus.running;

  bool get canStart => !isActive;

  SystemCoreProcessState addEvent({
    required SystemCoreProcessStatus status,
    required SystemCoreLogEntry entry,
    String? errorMessage,
    bool clearError = false,
  }) {
    return SystemCoreProcessState(
      status: status,
      logEntries: [...logEntries, entry],
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }

  factory SystemCoreProcessState.initial({DateTime Function()? clock}) {
    final now = clock ?? DateTime.now;

    return SystemCoreProcessState(
      status: SystemCoreProcessStatus.ready,
      logEntries: [
        SystemCoreLogEntry(
          timestamp: now(),
          message: ' BOOTING OMNI_AI KERNEL...',
          level: SystemCoreLogLevel.neutral,
        ),
        SystemCoreLogEntry(
          timestamp: now(),
          message: ' LOADING NEURAL INTERFACE',
          level: SystemCoreLogLevel.neutral,
        ),
        SystemCoreLogEntry(
          timestamp: now(),
          message: ' ENCRYPTION LAYER: ACTIVE',
          level: SystemCoreLogLevel.success,
        ),
        SystemCoreLogEntry(
          timestamp: now(),
          message: ' SYSTEM READY_',
          level: SystemCoreLogLevel.accent,
        ),
      ],
    );
  }
}
