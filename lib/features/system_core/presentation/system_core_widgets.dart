import 'package:flutter/material.dart';
import 'package:omni_ai/features/system_core/models/system_core_process_state.dart';
import 'package:omni_ai/features/system_core/presentation/system_core_palette.dart';

class SystemCoreTopBar extends StatelessWidget {
  const SystemCoreTopBar({required this.onHistoryPressed, super.key});

  final VoidCallback onHistoryPressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: SystemCorePalette.red,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: SystemCorePalette.red, blurRadius: 12),
                ],
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'NEXUS // 07',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 11,
                letterSpacing: 2,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        Row(
          children: [
            const Text(
              'SYS.01',
              style: TextStyle(
                color: SystemCorePalette.muted,
                fontSize: 11,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Run history',
              onPressed: onHistoryPressed,
              icon: const Icon(Icons.history, size: 18),
              color: SystemCorePalette.muted,
              constraints: const BoxConstraints.tightFor(width: 40, height: 40),
              padding: EdgeInsets.zero,
            ),
          ],
        ),
      ],
    );
  }
}

class SystemCoreStatusBadge extends StatelessWidget {
  const SystemCoreStatusBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: SystemCorePalette.green.withValues(alpha: 0.06),
        border: Border.all(
          color: SystemCorePalette.green.withValues(alpha: 0.55),
        ),
        boxShadow: [
          BoxShadow(
            color: SystemCorePalette.green.withValues(alpha: 0.08),
            blurRadius: 14,
          ),
        ],
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 7, color: SystemCorePalette.green),
          SizedBox(width: 9),
          Text(
            'STATUS: ONLINE',
            style: TextStyle(
              color: SystemCorePalette.green,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class SystemCoreTerminalWindow extends StatelessWidget {
  const SystemCoreTerminalWindow({required this.entries, super.key});

  final List<SystemCoreLogEntry> entries;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: SystemCorePalette.panel,
        border: Border.all(color: SystemCorePalette.red.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: SystemCorePalette.red.withValues(alpha: 0.1),
            blurRadius: 22,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.025),
              border: Border(
                bottom: BorderSide(
                  color: SystemCorePalette.red.withValues(alpha: 0.25),
                ),
              ),
            ),
            child: const Row(
              children: [
                _WindowDot(color: SystemCorePalette.red),
                SizedBox(width: 6),
                _WindowDot(color: Color(0xFFFFB800)),
                SizedBox(width: 6),
                _WindowDot(color: SystemCorePalette.green),
                SizedBox(width: 12),
                Text(
                  'root@omni:~',
                  style: TextStyle(
                    color: SystemCorePalette.muted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final entry in entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 13),
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          height: 1.4,
                        ),
                        children: [
                          TextSpan(
                            text: '${_formatTimestamp(entry.timestamp)} ',
                            style: const TextStyle(
                              color: SystemCorePalette.muted,
                            ),
                          ),
                          TextSpan(
                            text: entry.message,
                            style: TextStyle(
                              color: _logLevelColor(entry.level),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 2),
                const Text(
                  'root@omni:~# _',
                  style: TextStyle(
                    color: SystemCorePalette.green,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WindowDot extends StatelessWidget {
  const _WindowDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class SystemCoreRunButton extends StatelessWidget {
  const SystemCoreRunButton({
    required this.status,
    required this.onPressed,
    super.key,
  });

  final SystemCoreProcessStatus status;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isActive = _isProcessActive(status);

    return SizedBox(
      width: double.infinity,
      height: 58,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: SystemCorePalette.red,
          side: const BorderSide(color: SystemCorePalette.red, width: 1.3),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          backgroundColor: SystemCorePalette.red.withValues(alpha: 0.07),
          shadowColor: SystemCorePalette.red,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isActive ? Icons.stop_rounded : Icons.play_arrow_rounded,
              size: 19,
            ),
            const SizedBox(width: 9),
            Flexible(
              child: Text(
                _processButtonLabel(status),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatTimestamp(DateTime timestamp) {
  final localTime = timestamp.toLocal();
  final hours = localTime.hour.toString().padLeft(2, '0');
  final minutes = localTime.minute.toString().padLeft(2, '0');
  final seconds = localTime.second.toString().padLeft(2, '0');
  return '[$hours:$minutes:$seconds]';
}

Color _logLevelColor(SystemCoreLogLevel level) => switch (level) {
  SystemCoreLogLevel.neutral => Colors.white70,
  SystemCoreLogLevel.success => SystemCorePalette.green,
  SystemCoreLogLevel.accent => SystemCorePalette.red,
  SystemCoreLogLevel.error => SystemCorePalette.red,
};

String _processButtonLabel(SystemCoreProcessStatus status) => switch (status) {
  SystemCoreProcessStatus.ready => 'ЗАПУСТИТЬ АВТО-ПРОЦЕСС',
  SystemCoreProcessStatus.starting => 'ОТМЕНИТЬ ЗАПУСК',
  SystemCoreProcessStatus.running => 'ОТМЕНИТЬ АВТО-ПРОЦЕСС',
  SystemCoreProcessStatus.completed => 'ЗАПУСТИТЬ СНОВА',
  SystemCoreProcessStatus.failed => 'ПОВТОРИТЬ ЗАПУСК',
  SystemCoreProcessStatus.cancelled => 'ЗАПУСТИТЬ СНОВА',
};

bool _isProcessActive(SystemCoreProcessStatus status) =>
    status == SystemCoreProcessStatus.starting ||
    status == SystemCoreProcessStatus.running;
