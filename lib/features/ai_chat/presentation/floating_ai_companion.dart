import 'package:flutter/material.dart';
import 'package:omni_ai/core/di/app_dependencies.dart';
import 'package:omni_ai/features/ai_chat/presentation/ai_chat_page.dart';
import 'package:omni_ai/features/system_core/presentation/system_core_palette.dart';

/// Draggable AI companion that opens the existing chat without leaving a page.
class FloatingAICompanion extends StatefulWidget {
  const FloatingAICompanion({required this.dependencies, super.key});
  final AppDependencies dependencies;

  @override
  State<FloatingAICompanion> createState() => _FloatingAICompanionState();
}

class _FloatingAICompanionState extends State<FloatingAICompanion> {
  Offset? _position;
  bool _hidden = false;
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    if (_hidden) {
      return Positioned(
        right: 8,
        bottom: 12,
        child: IconButton(
          tooltip: 'Показать AI-компаньона',
          onPressed: () => setState(() => _hidden = false),
          style: IconButton.styleFrom(
            backgroundColor: SystemCorePalette.panelElevated,
            foregroundColor: SystemCorePalette.green,
          ),
          icon: const Icon(Icons.smart_toy_outlined),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxX = (constraints.maxWidth - 62).clamp(8.0, double.infinity);
        final maxY = (constraints.maxHeight - 70).clamp(8.0, double.infinity);
        final pos =
            _position ??
            Offset(maxX, (constraints.maxHeight * .62).clamp(8.0, maxY));
        final left = pos.dx.clamp(8.0, maxX);
        final top = pos.dy.clamp(8.0, maxY);
        return Stack(
          children: [
            if (_open)
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    12,
                    12,
                    12,
                    constraints.maxHeight > 620 ? 76 : 12,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Material(
                        color: SystemCorePalette.panel,
                        elevation: 14,
                        clipBehavior: Clip.antiAlias,
                        borderRadius: BorderRadius.circular(22),
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
                              decoration: const BoxDecoration(
                                color: SystemCorePalette.panelElevated,
                                border: Border(
                                  bottom: BorderSide(
                                    color: SystemCorePalette.border,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.smart_toy_rounded,
                                    color: SystemCorePalette.green,
                                  ),
                                  const SizedBox(width: 10),
                                  const Expanded(
                                    child: Text(
                                      'OMNI AI · помощник',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Свернуть',
                                    onPressed: () =>
                                        setState(() => _open = false),
                                    icon: const Icon(Icons.remove),
                                  ),
                                  IconButton(
                                    tooltip: 'Скрыть помощника',
                                    onPressed: () => setState(() {
                                      _open = false;
                                      _hidden = true;
                                    }),
                                    icon: const Icon(Icons.close),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: AIChatPage(
                                dependencies: widget.dependencies,
                                compactHeader: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              )
            else
              Positioned(
                left: left,
                top: top,
                child: GestureDetector(
                  onPanUpdate: (details) => setState(() {
                    _position = Offset(
                      (left + details.delta.dx).clamp(8.0, maxX),
                      (top + details.delta.dy).clamp(8.0, maxY),
                    );
                  }),
                  child: Tooltip(
                    message:
                        'Перетащите помощника или нажмите, чтобы открыть чат',
                    child: Material(
                      color: SystemCorePalette.panelElevated,
                      elevation: 10,
                      shadowColor: SystemCorePalette.green.withValues(
                        alpha: 0.24,
                      ),
                      shape: CircleBorder(
                        side: BorderSide(
                          color: SystemCorePalette.green.withValues(
                            alpha: 0.42,
                          ),
                        ),
                      ),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => setState(() => _open = true),
                        child: SizedBox(
                          width: 54,
                          height: 54,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              const Icon(
                                Icons.smart_toy_rounded,
                                size: 29,
                                color: SystemCorePalette.green,
                              ),
                              Positioned(
                                right: 7,
                                bottom: 7,
                                child: Container(
                                  width: 7,
                                  height: 7,
                                  decoration: const BoxDecoration(
                                    color: SystemCorePalette.mint,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
