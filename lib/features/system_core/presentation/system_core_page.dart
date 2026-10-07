import 'dart:async';

import 'package:flutter/material.dart';
import 'package:omni_ai/features/system_core/models/system_core_process_state.dart';
import 'package:omni_ai/features/system_core/presentation/system_core_palette.dart';
import 'package:omni_ai/features/system_core/presentation/system_core_widgets.dart';
import 'package:omni_ai/features/system_core/services/system_core_process_service.dart';

class SystemCorePage extends StatefulWidget {
  const SystemCorePage({super.key, this.service});

  final SystemCoreProcessService? service;

  @override
  State<SystemCorePage> createState() => _SystemCorePageState();
}

class _SystemCorePageState extends State<SystemCorePage> {
  late final SystemCoreProcessService _service;
  late final bool _ownsService;
  late final StreamSubscription<SystemCoreProcessState> _subscription;
  late SystemCoreProcessState _process;

  @override
  void initState() {
    super.initState();
    _ownsService = widget.service == null;
    _service = widget.service ?? SystemCoreProcessService();
    _process = _service.state;
    _subscription = _service.states.listen((process) {
      if (mounted) setState(() => _process = process);
    });
  }

  void _handleProcessAction() {
    if (_process.isActive) {
      _service.cancel();
    } else {
      unawaited(_service.start());
    }
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    if (_ownsService) unawaited(_service.dispose());
    super.dispose();
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
                    onPressed: _handleProcessAction,
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
