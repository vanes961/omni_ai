import 'package:flutter/material.dart';
import 'package:omni_ai/features/run_history/models/process_run_record.dart';
import 'package:omni_ai/features/run_history/repositories/run_history_repository.dart';
import 'package:omni_ai/features/system_core/models/system_core_process_state.dart';
import 'package:omni_ai/features/system_core/presentation/system_core_palette.dart';

class RunHistoryPage extends StatelessWidget {
  const RunHistoryPage({required this.repository, super.key});

  final RunHistoryRepository repository;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RUN HISTORY'),
        backgroundColor: SystemCorePalette.background,
      ),
      body: StreamBuilder<List<ProcessRunRecord>>(
        stream: repository.watch(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('FAILED TO LOAD RUN HISTORY'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final records = snapshot.data!;
          if (records.isEmpty) return const _EmptyHistory();

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                itemCount: records.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 10),
                itemBuilder: (context, index) => _RunHistoryEntry(
                  record: records[index],
                  onDelete: () => repository.delete(records[index].id),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history, color: SystemCorePalette.muted, size: 32),
          SizedBox(height: 12),
          Text(
            'NO RUNS RECORDED',
            style: TextStyle(
              color: SystemCorePalette.muted,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _RunHistoryEntry extends StatelessWidget {
  const _RunHistoryEntry({required this.record, required this.onDelete});

  final ProcessRunRecord record;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: SystemCorePalette.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: SystemCorePalette.muted.withValues(alpha: 0.3)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          leading: Icon(
            _statusIcon(record.status),
            color: _statusColor(record.status),
            size: 18,
          ),
          title: Text(
            _statusLabel(record.status),
            style: TextStyle(
              color: _statusColor(record.status),
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: Text(
            '${_formatDateTime(record.startedAt)}  //  ${record.id}',
            style: const TextStyle(
              color: SystemCorePalette.muted,
              fontSize: 10,
            ),
          ),
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: 'Delete run',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 18),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                record.duration == null
                    ? 'IN PROGRESS'
                    : 'DURATION  ${_formatDuration(record.duration!)}',
                style: const TextStyle(
                  color: SystemCorePalette.muted,
                  fontSize: 10,
                ),
              ),
            ),
            if (record.errorMessage case final errorMessage?) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  errorMessage,
                  style: const TextStyle(
                    color: SystemCorePalette.red,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            for (final entry in record.logEntries)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatTime(entry.timestamp),
                      style: const TextStyle(
                        color: SystemCorePalette.muted,
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        entry.message,
                        style: TextStyle(
                          color: _logLevelColor(entry.level),
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

IconData _statusIcon(SystemCoreProcessStatus status) => switch (status) {
  SystemCoreProcessStatus.ready => Icons.schedule,
  SystemCoreProcessStatus.starting => Icons.play_circle_outline,
  SystemCoreProcessStatus.running => Icons.autorenew,
  SystemCoreProcessStatus.completed => Icons.check_circle_outline,
  SystemCoreProcessStatus.failed => Icons.error_outline,
  SystemCoreProcessStatus.cancelled => Icons.cancel_outlined,
  SystemCoreProcessStatus.timeout => Icons.timer_off_outlined,
};

Color _statusColor(SystemCoreProcessStatus status) => switch (status) {
  SystemCoreProcessStatus.ready => SystemCorePalette.muted,
  SystemCoreProcessStatus.starting ||
  SystemCoreProcessStatus.running => SystemCorePalette.green,
  SystemCoreProcessStatus.completed => SystemCorePalette.green,
  SystemCoreProcessStatus.failed => SystemCorePalette.red,
  SystemCoreProcessStatus.cancelled => SystemCorePalette.muted,
  SystemCoreProcessStatus.timeout => SystemCorePalette.red,
};

String _statusLabel(SystemCoreProcessStatus status) =>
    status.name.toUpperCase();

Color _logLevelColor(SystemCoreLogLevel level) => switch (level) {
  SystemCoreLogLevel.neutral => Colors.white70,
  SystemCoreLogLevel.success => SystemCorePalette.green,
  SystemCoreLogLevel.accent => SystemCorePalette.red,
  SystemCoreLogLevel.error => SystemCorePalette.red,
};

String _formatDateTime(DateTime dateTime) {
  final localDateTime = dateTime.toLocal();
  return '${localDateTime.year.toString().padLeft(4, '0')}-'
      '${localDateTime.month.toString().padLeft(2, '0')}-'
      '${localDateTime.day.toString().padLeft(2, '0')}  '
      '${_formatTime(localDateTime)}';
}

String _formatTime(DateTime dateTime) {
  final localDateTime = dateTime.toLocal();
  return '${localDateTime.hour.toString().padLeft(2, '0')}:'
      '${localDateTime.minute.toString().padLeft(2, '0')}:'
      '${localDateTime.second.toString().padLeft(2, '0')}';
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes.toString().padLeft(2, '0');
  final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
