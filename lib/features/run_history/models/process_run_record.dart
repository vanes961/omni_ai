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

  Map<String, Object?> toJson() => {
    'id': id,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'finishedAt': finishedAt?.toUtc().toIso8601String(),
    'status': status.name,
    'errorMessage': errorMessage,
    'logEntries': [
      for (final entry in logEntries)
        {
          'timestamp': entry.timestamp.toUtc().toIso8601String(),
          'message': entry.message,
          'level': entry.level.name,
        },
    ],
  };

  factory ProcessRunRecord.fromJson(Map<String, Object?> json) {
    final rawEntries = json['logEntries'];
    if (rawEntries is! List) {
      throw const FormatException('Run log entries must be a list.');
    }

    final rawFinishedAt = json['finishedAt'];
    final rawErrorMessage = json['errorMessage'];

    return ProcessRunRecord(
      id: json['id'] as String,
      startedAt: DateTime.parse(json['startedAt'] as String),
      finishedAt: rawFinishedAt == null
          ? null
          : DateTime.parse(rawFinishedAt as String),
      status: SystemCoreProcessStatus.values.byName(json['status'] as String),
      errorMessage: rawErrorMessage as String?,
      logEntries: [
        for (final rawEntry in rawEntries)
          _logEntryFromJson(Map<String, Object?>.from(rawEntry as Map)),
      ],
    );
  }

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

SystemCoreLogEntry _logEntryFromJson(Map<String, Object?> json) {
  return SystemCoreLogEntry(
    timestamp: DateTime.parse(json['timestamp'] as String),
    message: json['message'] as String,
    level: SystemCoreLogLevel.values.byName(json['level'] as String),
  );
}
