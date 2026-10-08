import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:omni_ai/features/media/data/media_item.dart';
import 'package:omni_ai/features/media/services/media_headers.dart';
import 'package:omni_ai/features/media/services/media_search_service.dart';
import 'package:omni_ai/features/onboarding/data/user_preferences.dart';
import 'package:omni_ai/features/system_core/presentation/system_core_palette.dart';
import 'package:video_player/video_player.dart';

typedef MediaPlayerFactory = MediaPlaybackController Function(Uri source);

abstract interface class MediaPlaybackController {
  bool get isInitialized;
  bool get isPlaying;
  double get aspectRatio;

  Future<void> initialize();

  Future<void> play();

  Future<void> pause();

  Future<void> dispose();

  Widget buildView();
}

class PlayerPage extends StatefulWidget {
  const PlayerPage({
    required this.item,
    required this.preferences,
    this.searchService = const MediaSearchService(),
    this.playerFactory,
    super.key,
  });

  final MediaItem item;
  final UserPreferences preferences;
  final MediaSearchService searchService;
  final MediaPlayerFactory? playerFactory;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late String? _selectedVoiceover;
  MediaPlaybackController? _player;
  Object? _playerError;
  bool _isLoading = true;
  int _selectedEpisode = 0;
  int _playerGeneration = 0;

  bool get _hasEpisodes => widget.item.episodes.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _selectedVoiceover = widget.searchService.preferredVoiceover(
      widget.item,
      widget.preferences,
    );
    _loadEpisode(0);
  }

  @override
  void dispose() {
    _playerGeneration++;
    _player?.dispose();
    super.dispose();
  }

  Future<void> _loadEpisode(int episodeIndex) async {
    final generation = ++_playerGeneration;
    final oldPlayer = _player;
    final episode = _hasEpisodes ? widget.item.episodes[episodeIndex] : null;
    final source = episode?.videoUrl ?? widget.item.videoUrl;
    final fallbackUrls = [
      ...widget.item.videoFallbackUrls,
      if (episode != null) ...episode.videoFallbackUrls,
    ];
    final sources = <String>{
      source.trim(),
      ...fallbackUrls.map((url) => url.trim()),
    }.where((url) => url.isNotEmpty).toList(growable: false);
    final playerFactory = widget.playerFactory ?? _videoPlayerFactory;

    setState(() {
      _selectedEpisode = episodeIndex;
      _isLoading = true;
      _playerError = null;
      _player = null;
    });
    await _disposePlayer(oldPlayer);

    Object? playerError;
    for (var index = 0; index < sources.length; index++) {
      if (!mounted || generation != _playerGeneration) return;
      MediaPlaybackController? nextPlayer;
      try {
        nextPlayer = playerFactory(Uri.parse(sources[index]));
        await nextPlayer.initialize();
        if (!mounted || generation != _playerGeneration) {
          await _disposePlayer(nextPlayer);
          return;
        }
        setState(() {
          _player = nextPlayer;
          _isLoading = false;
        });
        return;
      } on PlatformException catch (error) {
        playerError = error;
        await _disposePlayer(nextPlayer);
      } on Object catch (error) {
        playerError = error;
        await _disposePlayer(nextPlayer);
      }
    }
    if (!mounted || generation != _playerGeneration) return;
    setState(() {
      _playerError = playerError;
      _isLoading = false;
    });
  }

  Future<void> _disposePlayer(MediaPlaybackController? player) async {
    if (player == null) return;
    try {
      await player.dispose();
    } on Object {
      // A dispose failure must not prevent trying the next stream source.
    }
  }

  @override
  Widget build(BuildContext context) {
    final episodes = widget.item.episodes;

    return Scaffold(
      backgroundColor: SystemCorePalette.background,
      appBar: AppBar(
        title: const Text('OMNI // PLAYER'),
        backgroundColor: SystemCorePalette.background,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _buildPlayerSurface(),
          const SizedBox(height: 18),
          Text(
            widget.item.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '${widget.item.type}  ·  ★ ${widget.item.rating.toStringAsFixed(1)}',
            style: const TextStyle(
              color: SystemCorePalette.muted,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 20),
          if (episodes.length > 1) ...[
            const _PlayerSectionLabel('ВЫБОР СЕРИИ'),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              key: const ValueKey('episode-selector'),
              initialValue: _selectedEpisode,
              isExpanded: true,
              dropdownColor: SystemCorePalette.panel,
              decoration: _selectorDecoration(),
              items: [
                for (var index = 0; index < episodes.length; index++)
                  DropdownMenuItem(
                    value: index,
                    child: Text(
                      episodes[index].label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (index) {
                if (index != null && index != _selectedEpisode) {
                  _loadEpisode(index);
                }
              },
            ),
            const SizedBox(height: 18),
          ],
          const _PlayerSectionLabel('ОЗВУЧКА'),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: const ValueKey('voiceover-selector'),
            initialValue: _selectedVoiceover,
            isExpanded: true,
            dropdownColor: SystemCorePalette.panel,
            decoration: _selectorDecoration(),
            items: [
              for (final voiceover in widget.item.voiceovers)
                DropdownMenuItem(
                  value: voiceover,
                  child: Text(
                    voiceover,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (voiceover) {
              if (voiceover != null) {
                setState(() => _selectedVoiceover = voiceover);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerSurface() {
    final player = _player;
    return AspectRatio(
      aspectRatio: player?.aspectRatio ?? 16 / 9,
      child: DecoratedBox(
        decoration: const BoxDecoration(color: Colors.black),
        child: Stack(
          fit: StackFit.expand,
          alignment: Alignment.center,
          children: [
            if (player?.isInitialized ?? false)
              player!.buildView()
            else if (_isLoading)
              const Center(
                child: CircularProgressIndicator(
                  color: SystemCorePalette.green,
                ),
              )
            else
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.play_disabled,
                        color: SystemCorePalette.muted,
                        size: 34,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'ВИДЕО НЕДОСТУПНО НА ЭТОЙ ПЛАТФОРМЕ',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                        ),
                      ),
                      if (_playerError != null) ...[
                        const SizedBox(height: 5),
                        Text(
                          _playerError.runtimeType.toString(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: SystemCorePalette.muted,
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            if (player?.isInitialized ?? false)
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  height: 52,
                  color: Colors.black54,
                  alignment: Alignment.center,
                  child: IconButton(
                    tooltip: player!.isPlaying ? 'Пауза' : 'Воспроизвести',
                    onPressed: () => setState(() {
                      if (player.isPlaying) {
                        player.pause();
                      } else {
                        player.play();
                      }
                    }),
                    icon: Icon(
                      player.isPlaying ? Icons.pause : Icons.play_arrow,
                    ),
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  InputDecoration _selectorDecoration() => InputDecoration(
    filled: true,
    fillColor: SystemCorePalette.panel,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: const OutlineInputBorder(borderRadius: BorderRadius.zero),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: BorderSide(
        color: SystemCorePalette.muted.withValues(alpha: 0.4),
      ),
    ),
  );
}

class _PlayerSectionLabel extends StatelessWidget {
  const _PlayerSectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: SystemCorePalette.muted,
        fontSize: 10,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}

MediaPlaybackController _videoPlayerFactory(Uri source) {
  return _VideoPlayerAdapter(source);
}

class _VideoPlayerAdapter implements MediaPlaybackController {
  _VideoPlayerAdapter(Uri source)
    : _controller = VideoPlayerController.networkUrl(
        source,
        httpHeaders: MediaHeaders.getHeaders(source.toString()),
      );

  final VideoPlayerController _controller;

  @override
  bool get isInitialized => _controller.value.isInitialized;

  @override
  bool get isPlaying => _controller.value.isPlaying;

  @override
  double get aspectRatio => _controller.value.aspectRatio > 0
      ? _controller.value.aspectRatio
      : 16 / 9;

  @override
  Future<void> initialize() => _controller.initialize();

  @override
  Future<void> play() => _controller.play();

  @override
  Future<void> pause() => _controller.pause();

  @override
  Future<void> dispose() => _controller.dispose();

  @override
  Widget buildView() => VideoPlayer(_controller);
}
