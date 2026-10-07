import 'package:flutter/material.dart';

const _background = Color(0xFF050505);
const _panel = Color(0xFF0C0C0F);
const _red = Color(0xFFFF0033);
const _green = Color(0xFF00FF66);
const _muted = Color(0xFF77777F);

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OMNI_AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _background,
        colorScheme: const ColorScheme.dark(
          primary: _red,
          secondary: _green,
          surface: _panel,
        ),
        fontFamily: 'monospace',
        useMaterial3: true,
      ),
      home: const SystemCorePage(),
    );
  }
}

class SystemCorePage extends StatefulWidget {
  const SystemCorePage({super.key});

  @override
  State<SystemCorePage> createState() => _SystemCorePageState();
}

class _SystemCorePageState extends State<SystemCorePage> {
  bool _processStarted = false;

  void _startProcess() {
    setState(() => _processStarted = true);
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
                  const _TopBar(),
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
                      shadows: [Shadow(color: _red, blurRadius: 18)],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const _StatusBadge(),
                  const SizedBox(height: 40),
                  _SectionHeading(
                    index: '01',
                    title: 'EXECUTION LOG',
                    accent: _red,
                  ),
                  const SizedBox(height: 14),
                  _TerminalWindow(processStarted: _processStarted),
                  const SizedBox(height: 26),
                  _RunButton(
                    processStarted: _processStarted,
                    onPressed: _startProcess,
                  ),
                  const SizedBox(height: 18),
                  const Center(
                    child: Text(
                      'AUTHORIZED ACCESS ONLY  //  BUILD 0.01',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _muted,
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

class _TopBar extends StatelessWidget {
  const _TopBar();

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
                color: _red,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: _red, blurRadius: 12)],
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
        const Text(
          'SYS.01',
          style: TextStyle(color: _muted, fontSize: 11, letterSpacing: 1.5),
        ),
      ],
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
      style: const TextStyle(color: _muted, fontSize: 10, letterSpacing: 2),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: _green.withValues(alpha: 0.06),
        border: Border.all(color: _green.withValues(alpha: 0.55)),
        boxShadow: [
          BoxShadow(color: _green.withValues(alpha: 0.08), blurRadius: 14),
        ],
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 7, color: _green),
          SizedBox(width: 9),
          Text(
            'STATUS: ONLINE',
            style: TextStyle(
              color: _green,
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

class _TerminalWindow extends StatelessWidget {
  const _TerminalWindow({required this.processStarted});

  final bool processStarted;

  @override
  Widget build(BuildContext context) {
    final lines = processStarted
        ? const [
            ('[19:28:01]', ' AUTO-PROCESS INITIALIZED', _green),
            ('[19:28:02]', ' NEURAL CORE SYNCHRONIZED', Colors.white70),
            ('[19:28:03]', ' TASK QUEUE: READY', _green),
            ('[19:28:04]', ' AWAITING NEXT CYCLE_', _red),
          ]
        : const [
            ('[19:27:41]', ' BOOTING OMNI_AI KERNEL...', Colors.white70),
            ('[19:27:42]', ' LOADING NEURAL INTERFACE', Colors.white70),
            ('[19:27:43]', ' ENCRYPTION LAYER: ACTIVE', _green),
            ('[19:27:44]', ' SYSTEM READY_', _red),
          ];

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _panel,
        border: Border.all(color: _red.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(color: _red.withValues(alpha: 0.1), blurRadius: 22),
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
                bottom: BorderSide(color: _red.withValues(alpha: 0.25)),
              ),
            ),
            child: const Row(
              children: [
                _WindowDot(color: _red),
                SizedBox(width: 6),
                _WindowDot(color: Color(0xFFFFB800)),
                SizedBox(width: 6),
                _WindowDot(color: _green),
                SizedBox(width: 12),
                Text(
                  'root@omni:~',
                  style: TextStyle(color: _muted, fontSize: 11),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in lines)
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
                            text: '${line.$1} ',
                            style: const TextStyle(color: _muted),
                          ),
                          TextSpan(
                            text: line.$2,
                            style: TextStyle(color: line.$3),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 2),
                const Text(
                  'root@omni:~# _',
                  style: TextStyle(
                    color: _green,
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

class _RunButton extends StatelessWidget {
  const _RunButton({required this.processStarted, required this.onPressed});

  final bool processStarted;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: _red,
          side: const BorderSide(color: _red, width: 1.3),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          backgroundColor: _red.withValues(alpha: 0.07),
          shadowColor: _red,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.play_arrow_rounded, size: 19),
            const SizedBox(width: 9),
            Flexible(
              child: Text(
                processStarted
                    ? 'АВТО-ПРОЦЕСС ЗАПУЩЕН'
                    : 'ЗАПУСТИТЬ АВТО-ПРОЦЕСС',
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
