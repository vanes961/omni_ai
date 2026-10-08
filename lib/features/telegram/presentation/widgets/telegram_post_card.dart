import 'package:flutter/material.dart';
import 'package:omni_ai/features/system_core/presentation/system_core_palette.dart';
import 'package:omni_ai/features/telegram/data/telegram_post.dart';
import 'package:url_launcher/url_launcher.dart';

typedef TelegramSourceLauncher = Future<bool> Function(Uri uri);

class TelegramPostCard extends StatelessWidget {
  const TelegramPostCard({required this.post, this.sourceLauncher, super.key});

  final TelegramPost post;
  final TelegramSourceLauncher? sourceLauncher;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: SystemCorePalette.panel,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  color: SystemCorePalette.green.withValues(alpha: 0.12),
                  child: const Icon(
                    Icons.send_rounded,
                    size: 15,
                    color: SystemCorePalette.green,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        post.channelName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatTimestamp(post.timestamp),
                        style: const TextStyle(
                          color: SystemCorePalette.muted,
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ),
                if (post.isPinned) ...[
                  const Icon(
                    Icons.push_pin_outlined,
                    size: 14,
                    color: SystemCorePalette.green,
                  ),
                  const SizedBox(width: 8),
                ],
                IconButton(
                  key: ValueKey('source-${post.id}'),
                  tooltip: 'Открыть первоисточник',
                  onPressed: post.sourceUrl == null
                      ? null
                      : () => _openSource(context, Uri.parse(post.sourceUrl!)),
                  icon: const Icon(Icons.open_in_new, size: 17),
                  color: SystemCorePalette.muted,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              post.text,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            if (post.mediaUrl case final mediaUrl?) ...[
              const SizedBox(height: 12),
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  mediaUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    color: SystemCorePalette.background,
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.image_not_supported_outlined,
                      color: SystemCorePalette.muted,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openSource(BuildContext context, Uri uri) async {
    try {
      final launched = await (sourceLauncher ?? _launchSource)(uri);
      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось открыть первоисточник')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось открыть первоисточник')),
        );
      }
    }
  }
}

Future<bool> _launchSource(Uri uri) {
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

String _formatTimestamp(DateTime timestamp) {
  final local = timestamp.toLocal();
  final hours = local.hour.toString().padLeft(2, '0');
  final minutes = local.minute.toString().padLeft(2, '0');
  return '$hours:$minutes';
}
