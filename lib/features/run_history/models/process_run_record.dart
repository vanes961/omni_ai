import 'package:omni_ai/features/system_core/models/system_core_process_state.dart';

class ProcessRunRecord {
  ProcessRunRecord({
    required this.id,
    required this.startedAt,
    required this.status,
    required Iterable<SystemCoreLogEntry> logEntries,
    this.finishedAt,
    this.errorMessage,
  }) : logEntries = List.unmodifiable(logEntries);

  final String id;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final SystemCoreProcessStatus status;
  final List<SystemCoreLogEntry> logEntries;
  final String? errorMessage;

  Duration? get duration => finishedAt?.difference(startedAt);

  ProcessRunRecord copyWith({
    DateTime? finishedAt,
    SystemCoreProcessStatus? status,
    Iterable<SystemCoreLogEntry>? logEntries,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ProcessRunRecord(
      id: id,
      startedAt: startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      status: status ?? this.status,
      logEntries: logEntries ?? this.logEntries,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}
