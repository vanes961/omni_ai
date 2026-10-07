import 'package:flutter/material.dart';
import 'package:omni_ai/features/system_core/models/system_core_process_state.dart';
import 'package:omni_ai/features/system_core/presentation/system_core_palette.dart';
import 'package:omni_ai/features/system_core/presentation/system_core_widgets.dart';

class SystemCorePage extends StatefulWidget {
  const SystemCorePage({super.key});

  @override
  State<SystemCorePage> createState() => _SystemCorePageState();
}

class _SystemCorePageState extends State<SystemCorePage> {
  SystemCoreProcessState _process = SystemCoreProcessState.initial();

  void _startProcess() {
    setState(() => _process = _process.start());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SystemCoreTopBar(),
                  const SizedBox(height: 48),
                  const _Eyebrow('AUTONOMOUS INTELLIGENCE PLATFORM'),
                  const SizedBox(height: 14),
                  const Text(
                    '// OMNI_AI : SYS_CORE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 27,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.2,
                      shadows: [
                        Shadow(color: SystemCorePalette.red, blurRadius: 18),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const SystemCoreStatusBadge(),
                  const SizedBox(height: 40),
                  const _SectionHeading(
                    index: '01',
                    title: 'EXECUTION LOG',
                    accent: SystemCorePalette.red,
                  ),
                  const SizedBox(height: 14),
                  SystemCoreTerminalWindow(entries: _process.logEntries),
                  const SizedBox(height: 26),
                  SystemCoreRunButton(
                    status: _process.status,
                    onPressed: _startProcess,
                  ),
                  const SizedBox(height: 18),
                  const Center(
                    child: Text(
                      'AUTHORIZED ACCESS ONLY  //  BUILD 0.01',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: SystemCorePalette.muted,
                        fontSize: 10,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: SystemCorePalette.muted,
        fontSize: 10,
        letterSpacing: 2,
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.index,
    required this.title,
    required this.accent,
  });

  final String index;
  final String title;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          index,
          style: TextStyle(color: accent, fontSize: 11, letterSpacing: 1.5),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(height: 1, color: accent.withValues(alpha: 0.3)),
        ),
      ],
    );
  }
}
