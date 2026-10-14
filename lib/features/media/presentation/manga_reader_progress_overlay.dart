import 'package:flutter/material.dart';

/// Small, spoiler-free progress badge for a continuous manga reader.
///
/// Place inside the reader's [Stack]. It stays in the corner while the page
/// content scrolls beneath it. Tapping the badge reveals the page count.
class MangaReaderProgressOverlay extends StatefulWidget {
  const MangaReaderProgressOverlay({
    required this.chapterLabel,
    required this.currentPage,
    required this.totalPages,
    super.key,
  });

  final String chapterLabel;
  final int currentPage;
  final int totalPages;

  @override
  State<MangaReaderProgressOverlay> createState() =>
      _MangaReaderProgressOverlayState();
}

class _MangaReaderProgressOverlayState
    extends State<MangaReaderProgressOverlay> {
  bool _showDetails = false;

  int get _safeTotalPages => widget.totalPages < 0 ? 0 : widget.totalPages;

  int get _safeCurrentPage {
    if (_safeTotalPages == 0) return 0;
    return widget.currentPage.clamp(1, _safeTotalPages);
  }

  double? get _progress => _safeTotalPages == 0
      ? null
      : (_safeCurrentPage / _safeTotalPages).clamp(0.0, 1.0).toDouble();

  @override
  Widget build(BuildContext context) {
    final chapter = widget.chapterLabel.trim();
    final chapterText = chapter.isEmpty ? 'Чтение' : 'Глава $chapter';

    return Positioned(
      top: 10,
      right: 10,
      child: SafeArea(
        child: Semantics(
          button: true,
          label: _safeTotalPages == 0
              ? chapterText
              : '$chapterText, страница $_safeCurrentPage из $_safeTotalPages',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: const ValueKey('manga-reader-progress-toggle'),
              borderRadius: BorderRadius.circular(18),
              onTap: () => setState(() => _showDetails = !_showDetails),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xE6111714),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: const Color(0x8874D69A),
                    width: 0.8,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.menu_book_rounded,
                          size: 14,
                          color: Color(0xFF9BE6B4),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            chapterText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFF1F7F2),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (_showDetails) ...[
                          const SizedBox(width: 8),
                          Text(
                            _safeTotalPages == 0
                                ? '—'
                                : '$_safeCurrentPage/$_safeTotalPages',
                            style: const TextStyle(
                              color: Color(0xFFB9C9BE),
                              fontSize: 10,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (_showDetails && _safeTotalPages > 0) ...[
                      const SizedBox(height: 6),
                      SizedBox(
                        width: 108,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: _progress,
                            minHeight: 3,
                            backgroundColor: const Color(0xFF354139),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              Color(0xFF74D69A),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
