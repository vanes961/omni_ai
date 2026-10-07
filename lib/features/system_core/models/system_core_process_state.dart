enum SystemCoreProcessStatus { ready, running }

enum SystemCoreLogLevel { neutral, success, accent }

class SystemCoreLogEntry {
  const SystemCoreLogEntry({
    required this.timestamp,
    required this.message,
    required this.level,
  });

  final String timestamp;
  final String message;
  final SystemCoreLogLevel level;
}

class SystemCoreProcessState {
  SystemCoreProcessState({
    required this.status,
    required Iterable<SystemCoreLogEntry> logEntries,
  }) : logEntries = List.unmodifiable(logEntries);

  final SystemCoreProcessStatus status;
  final List<SystemCoreLogEntry> logEntries;

  bool get isRunning => status == SystemCoreProcessStatus.running;

  factory SystemCoreProcessState.initial() {
    return SystemCoreProcessState(
      status: SystemCoreProcessStatus.ready,
      logEntries: const [
        SystemCoreLogEntry(
          timestamp: '[19:27:41]',
          message: ' BOOTING OMNI_AI KERNEL...',
          level: SystemCoreLogLevel.neutral,
        ),
        SystemCoreLogEntry(
          timestamp: '[19:27:42]',
          message: ' LOADING NEURAL INTERFACE',
          level: SystemCoreLogLevel.neutral,
        ),
        SystemCoreLogEntry(
          timestamp: '[19:27:43]',
          message: ' ENCRYPTION LAYER: ACTIVE',
          level: SystemCoreLogLevel.success,
        ),
        SystemCoreLogEntry(
          timestamp: '[19:27:44]',
          message: ' SYSTEM READY_',
          level: SystemCoreLogLevel.accent,
        ),
      ],
    );
  }

  SystemCoreProcessState start() {
    if (isRunning) return this;

    return SystemCoreProcessState(
      status: SystemCoreProcessStatus.running,
      logEntries: const [
        SystemCoreLogEntry(
          timestamp: '[19:28:01]',
          message: ' AUTO-PROCESS INITIALIZED',
          level: SystemCoreLogLevel.success,
        ),
        SystemCoreLogEntry(
          timestamp: '[19:28:02]',
          message: ' NEURAL CORE SYNCHRONIZED',
          level: SystemCoreLogLevel.neutral,
        ),
        SystemCoreLogEntry(
          timestamp: '[19:28:03]',
          message: ' TASK QUEUE: READY',
          level: SystemCoreLogLevel.success,
        ),
        SystemCoreLogEntry(
          timestamp: '[19:28:04]',
          message: ' AWAITING NEXT CYCLE_',
          level: SystemCoreLogLevel.accent,
        ),
      ],
    );
  }
}
