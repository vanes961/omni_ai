import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:omni_ai/features/media/data/media_item.dart';
import 'package:omni_ai/features/media/services/media_headers.dart';
import 'package:omni_ai/features/media/services/media_resume_position_store.dart';
import 'package:omni_ai/features/media/services/media_search_service.dart';
import 'package:omni_ai/features/media/services/media_segment_marker_store.dart';
import 'package:omni_ai/features/onboarding/data/user_preferences.dart';
import 'package:omni_ai/features/system_core/presentation/system_core_palette.dart';
import 'package:video_player/video_player.dart';

typedef MediaPlayerFactory = MediaPlaybackController Function(Uri source);

abstract interface class MediaPlaybackController {
  bool get isInitialized;
  bool get isPlaying;
  double get aspectRatio;
  Duration get position;
  Duration get duration;

  Future<void> initialize();

  Future<void> play();

  Future<void> pause();

  Future<void> seekTo(Duration position);

  Future<void> dispose();

  Widget buildView();
}

class PlayerPage extends StatefulWidget {
  const PlayerPage({
    required this.item,
    required this.preferences,
    this.searchService = const MediaSearchService(),
    this.playerFactory,
    this.resumePositionStore,
    this.segmentMarkerStore,
    super.key,
  });

  final MediaItem item;
  final UserPreferences preferences;
  final MediaSearchService searchService;
  final MediaPlayerFactory? playerFactory;
  final MediaResumePositionStore? resumePositionStore;
  final MediaSegmentMarkerStore? segmentMarkerStore;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> with WidgetsBindingObserver {
  late String? _selectedVoiceover;
  MediaPlaybackController? _player;
  Object? _playerError;
  bool _isLoading = true;
  int _selectedEpisode = 0;
  int _playerGeneration = 0;
  Timer? _progressTimer;
  final Set<int> _resumePromptedEpisodes = <int>{};
  final Set<int> _watchedEpisodes = <int>{};
  List<MediaSegmentMarker> _segmentMarkers = const [];
  final Map<MediaSegmentType, Duration> _pendingSegmentStarts = {};

  bool get _tracksEpisodeHistory {
    final type = widget.item.type.toLowerCase();
    return type.contains('сериал') ||
        type.contains('аниме') ||
        type.contains('series') ||
        type.contains('anime');
  }

  Future<void> _loadWatchedHistory() async {
    if (!_tracksEpisodeHistory || !_hasEpisodes) return;
    final watched = await _resumeStore.loadWatchedEpisodes(widget.item.id);
    if (!mounted) return;
    setState(() {
      _watchedEpisodes
        ..clear()
        ..addAll(
          watched.where(
            (index) => index >= 0 && index < widget.item.episodes.length,
          ),
        );
    });
  }

  MediaResumePositionStore get _resumeStore =>
      widget.resumePositionStore ?? SharedPreferencesMediaResumePositionStore();

  MediaSegmentMarkerStore get _segmentStore =>
      widget.segmentMarkerStore ?? SharedPreferencesMediaSegmentMarkerStore();

  bool get _hasEpisodes => widget.item.episodes.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadWatchedHistory());
    _progressTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(_saveProgress());
      if (mounted) setState(() {});
    });
    _selectedVoiceover = widget.searchService.preferredVoiceover(
      widget.item,
      widget.preferences,
    );
    _loadEpisode(0);
  }

  @override
  void dispose() {
    _playerGeneration++;
    WidgetsBinding.instance.removeObserver(this);
    _progressTimer?.cancel();
    unawaited(_saveProgress());
    _player?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(_saveProgress());
    }
  }

  Future<void> _saveProgress({
    MediaPlaybackController? player,
    int? episodeIndex,
  }) async {
    final activePlayer = player ?? _player;
    if (activePlayer == null || !activePlayer.isInitialized) return;
    final index = episodeIndex ?? _selectedEpisode;
    await _resumeStore.save(
      widget.item.id,
      index,
      activePlayer.position,
      activePlayer.duration,
    );
    final remaining = activePlayer.duration - activePlayer.position;
    if (_tracksEpisodeHistory &&
        _hasEpisodes &&
        activePlayer.duration > Duration.zero &&
        remaining <= const Duration(seconds: 15) &&
        index >= 0 &&
        index < widget.item.episodes.length) {
      await _resumeStore.markEpisodeWatched(widget.item.id, index);
      if (mounted && _watchedEpisodes.add(index)) {
        setState(() {});
      }
    }
  }

  Future<void> _offerResumeIfAvailable(
    MediaPlaybackController player,
    int episodeIndex,
    int generation,
  ) async {
    if (_resumePromptedEpisodes.contains(episodeIndex)) return;
    final savedPosition = await _resumeStore.load(widget.item.id, episodeIndex);
    if (!mounted || generation != _playerGeneration || savedPosition == null) {
      return;
    }
    _resumePromptedEpisodes.add(episodeIndex);
    final remaining = player.duration - savedPosition;
    if (savedPosition < const Duration(seconds: 10) ||
        (player.duration > Duration.zero &&
            remaining <= const Duration(seconds: 15))) {
      await _resumeStore.clear(widget.item.id, episodeIndex);
      return;
    }
    final shouldResume = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: SystemCorePalette.panel,
        title: const Text(
          'Продолжить просмотр?',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Вы остановились на ${_formatPosition(savedPosition)}.',
          style: const TextStyle(color: SystemCorePalette.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('НАЧАТЬ СНАЧАЛА'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('ПРОДОЛЖИТЬ'),
          ),
        ],
      ),
    );
    if (!mounted || generation != _playerGeneration) return;
    if (shouldResume == true) {
      await player.seekTo(savedPosition);
    } else {
      await _resumeStore.clear(widget.item.id, episodeIndex);
    }
  }

  String _formatPosition(Duration position) {
    final hours = position.inHours;
    final minutes = position.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = position.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0
        ? '$hours:$minutes:$seconds'
        : '${position.inMinutes}:$seconds';
  }

  Future<void> _loadEpisode(int episodeIndex) async {
    final generation = ++_playerGeneration;
    final oldPlayer = _player;
    final episode = _hasEpisodes ? widget.item.episodes[episodeIndex] : null;
    final defaultSource = episode?.videoUrl ?? widget.item.videoUrl;
    final availableVoiceovers = _availableVoiceoversFor(episode);
    final selectedVoiceover =
        availableVoiceovers.isNotEmpty &&
            !availableVoiceovers.contains(_selectedVoiceover)
        ? _preferredAvailableVoiceover(availableVoiceovers)
        : _selectedVoiceover;
    final voiceoverSource = selectedVoiceover == null
        ? null
        : episode?.voiceoverVideoUrls[selectedVoiceover] ??
              widget.item.voiceoverVideoUrls[selectedVoiceover];
    final source = voiceoverSource ?? defaultSource;
    final fallbackUrls = [
      if (voiceoverSource != null) defaultSource,
      ...widget.item.videoFallbackUrls,
      if (episode != null) ...episode.videoFallbackUrls,
    ];
    final sources = <String>{
      source.trim(),
      ...fallbackUrls.map((url) => url.trim()),
    }.where((url) => url.isNotEmpty).toList(growable: false);
    final playerFactory = widget.playerFactory ?? _videoPlayerFactory;

    unawaited(_saveProgress(player: oldPlayer, episodeIndex: _selectedEpisode));
    setState(() {
      _selectedEpisode = episodeIndex;
      _segmentMarkers = const [];
      _pendingSegmentStarts.clear();
      if (selectedVoiceover != null) {
        _selectedVoiceover = selectedVoiceover;
      }
      _isLoading = true;
      _playerError = null;
      _player = null;
    });
    await _disposePlayer(oldPlayer);
    final savedMarkers = await _segmentStore.load(widget.item.id, episodeIndex);
    if (!mounted || generation != _playerGeneration) return;
    setState(() => _segmentMarkers = savedMarkers);

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
        await _offerResumeIfAvailable(nextPlayer, episodeIndex, generation);
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

  MediaSegmentMarker? _activeMarker(
    MediaSegmentType type,
    MediaPlaybackController player,
  ) {
    for (final marker in _segmentMarkers) {
      if (marker.type == type &&
          player.position >= marker.start &&
          player.position < marker.end) {
        return marker;
      }
    }
    return null;
  }

  Future<void> _skipSegment(
    MediaPlaybackController player,
    MediaSegmentMarker marker,
  ) => _seekTo(player, marker.end);

  Future<void> _setSegmentBoundary(
    MediaSegmentType type, {
    required bool isStart,
  }) async {
    final player = _player;
    if (player == null || !player.isInitialized) return;
    final position = player.position;
    if (isStart) {
      setState(() => _pendingSegmentStarts[type] = position);
      return;
    }
    final start = _pendingSegmentStarts.remove(type);
    if (start == null || position <= start) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Сначала отметьте начало сегмента.')),
        );
      }
      return;
    }
    final marker = MediaSegmentMarker(type: type, start: start, end: position);
    final markers = [
      ..._segmentMarkers.where((item) => item.type != type),
      marker,
    ]..sort((a, b) => a.start.compareTo(b.start));
    await _segmentStore.save(widget.item.id, _selectedEpisode, markers);
    if (!mounted) return;
    setState(() => _segmentMarkers = markers);
  }

  Widget _buildSegmentEditor() {
    return ExpansionTile(
      key: const ValueKey('segment-marker-editor'),
      collapsedIconColor: SystemCorePalette.green,
      iconColor: SystemCorePalette.green,
      title: const Text(
        'РАЗМЕТКА ВСТУПЛЕНИЯ И ТИТРОВ',
        style: TextStyle(
          color: SystemCorePalette.muted,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
      children: [
        for (final type in MediaSegmentType.values) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                type == MediaSegmentType.intro
                    ? 'Вступление'
                    : 'Финальные титры',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                key: ValueKey('mark-${type.name}-start'),
                onPressed: () => _setSegmentBoundary(type, isStart: true),
                child: Text(
                  _pendingSegmentStarts.containsKey(type)
                      ? 'Начало отмечено'
                      : 'Отметить начало',
                ),
              ),
              OutlinedButton(
                key: ValueKey('mark-${type.name}-end'),
                onPressed: () => _setSegmentBoundary(type, isStart: false),
                child: const Text('Отметить конец'),
              ),
            ],
          ),
        ],
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'Метки сохраняются для выбранного фильма или серии и используются при следующем просмотре.',
            style: TextStyle(color: SystemCorePalette.muted, fontSize: 11),
          ),
        ),
      ],
    );
  }

  Future<void> _seekTo(
    MediaPlaybackController player,
    Duration position,
  ) async {
    try {
      await player.seekTo(position);
      if (mounted && identical(_player, player)) {
        setState(() => _playerError = null);
      }
    } on Object catch (error) {
      if (mounted && identical(_player, player)) {
        setState(() => _playerError = error);
      }
    }
  }

  Future<void> _togglePlayback(MediaPlaybackController player) async {
    try {
      if (player.isPlaying) {
        await player.pause();
      } else {
        await player.play();
      }
      if (mounted && identical(_player, player)) {
        setState(() => _playerError = null);
      }
    } on Object catch (error) {
      if (mounted && identical(_player, player)) {
        setState(() => _playerError = error);
      }
    }
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
          if (_player?.isInitialized ?? false) _buildSegmentEditor(),
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
          if (_tracksEpisodeHistory && episodes.isNotEmpty) ...[
            Text(
              'ПРОСМОТРЕНО: ${_watchedEpisodes.length} ИЗ ${episodes.length} СЕРИЙ',
              key: const ValueKey('watched-episode-count'),
              style: const TextStyle(
                color: SystemCorePalette.green,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 12),
          ],
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
                      '${_watchedEpisodes.contains(index) ? '✓  ' : ''}${episodes[index].label}',
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
          if (widget.item.voiceovers.isNotEmpty) ...[
            const _PlayerSectionLabel('ОЗВУЧКА'),
            const SizedBox(height: 8),
            Builder(
              builder: (context) {
                final episode = _hasEpisodes
                    ? widget.item.episodes[_selectedEpisode]
                    : null;
                final availableVoiceovers = _availableVoiceoversFor(episode);
                if (availableVoiceovers.isEmpty) {
                  return Text(
                    widget.item.voiceovers.join(' · '),
                    style: const TextStyle(
                      color: SystemCorePalette.muted,
                      fontSize: 12,
                    ),
                  );
                }
                return DropdownButtonFormField<String>(
                  key: const ValueKey('voiceover-selector'),
                  initialValue: availableVoiceovers.contains(_selectedVoiceover)
                      ? _selectedVoiceover
                      : availableVoiceovers.first,
                  isExpanded: true,
                  dropdownColor: SystemCorePalette.panel,
                  decoration: _selectorDecoration(),
                  items: [
                    for (final voiceover in availableVoiceovers)
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
                    if (voiceover == null || voiceover == _selectedVoiceover) {
                      return;
                    }
                    setState(() => _selectedVoiceover = voiceover);
                    _loadEpisode(_selectedEpisode);
                  },
                );
              },
            ),
          ],
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
            if ((player?.isInitialized ?? false) && _playerError != null)
              Positioned(
                top: 8,
                left: 8,
                right: 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    border: Border.all(color: SystemCorePalette.green),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      'ОШИБКА ВОСПРОИЗВЕДЕНИЯ: ${_playerError.runtimeType}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ),
                ),
              ),
            if (player?.isInitialized ?? false) ...[
              if (_activeMarker(MediaSegmentType.intro, player)
                  case final marker?)
                Positioned(
                  top: 8,
                  right: 8,
                  child: FilledButton.tonalIcon(
                    key: const ValueKey('skip-intro-button'),
                    onPressed: () => _skipSegment(player, marker),
                    icon: const Icon(Icons.fast_forward, size: 18),
                    label: const Text('Пропустить вступление'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.black87,
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              if (_activeMarker(MediaSegmentType.credits, player)
                  case final marker?)
                Positioned(
                  bottom: 58,
                  right: 8,
                  child: FilledButton.tonalIcon(
                    key: const ValueKey('skip-credits-button'),
                    onPressed: () => _skipSegment(player, marker),
                    icon: const Icon(Icons.skip_next, size: 18),
                    label: const Text('Пропустить титры'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.black87,
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  height: 52,
                  color: Colors.black54,
                  alignment: Alignment.center,
                  child: IconButton(
                    tooltip: player.isPlaying ? 'Пауза' : 'Воспроизвести',
                    onPressed: () => _togglePlayback(player),
                    icon: Icon(
                      player.isPlaying ? Icons.pause : Icons.play_arrow,
                    ),
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<String> _availableVoiceoversFor(MediaEpisode? episode) {
    final episodeSources =
        episode?.voiceoverVideoUrls ?? const <String, String>{};
    final sources = episodeSources.isNotEmpty
        ? episodeSources
        : widget.item.voiceoverVideoUrls;
    return [
      for (final voiceover in widget.item.voiceovers)
        if (sources.containsKey(voiceover) &&
            sources[voiceover]!.trim().isNotEmpty)
          voiceover,
    ];
  }

  String? _preferredAvailableVoiceover(List<String> available) {
    for (final preferred in widget.preferences.voiceDubbing) {
      for (final voiceover in available) {
        if (voiceover.toLowerCase() == preferred.trim().toLowerCase()) {
          return voiceover;
        }
      }
    }
    return available.first;
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
  Duration get position => _controller.value.position;

  @override
  Duration get duration => _controller.value.duration;

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
  Future<void> seekTo(Duration position) => _controller.seekTo(position);

  @override
  Future<void> dispose() => _controller.dispose();

  @override
  Widget buildView() => VideoPlayer(_controller);
}
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:omni_ai/features/media/data/media_item.dart';
import 'package:omni_ai/features/onboarding/data/user_preferences.dart';

class MediaSearchService {
  const MediaSearchService({this.accessToken = _token});
  static const _token = String.fromEnvironment('TMDB_ACCESS_TOKEN');
  static const tmdbAttribution =
      'This product uses the TMDB API but is not endorsed or certified by TMDB.';
  static final Uri zonaCatalogUri = Uri.parse('https://w1.zona.im/');
  static const _api = 'https://api.themoviedb.org/3';
  static const _poster = 'https://image.tmdb.org/t/p/w500';
  final String accessToken;
  bool get isConfigured => accessToken.trim().isNotEmpty;
  static const Map<int, String> _genres = {
    28: 'Боевик',
    12: 'Приключения',
    16: 'Анимация',
    18: 'Драма',
    27: 'Ужасы',
    35: 'Комедия',
    36: 'История',
    37: 'Вестерн',
    53: 'Триллер',
    80: 'Криминал',
    99: 'Документальный',
    878: 'Фантастика',
    9648: 'Детектив',
    10402: 'Музыка',
    10749: 'Мелодрама',
    10751: 'Семейный',
    10752: 'Военный',
    10759: 'Боевик и приключения',
    10762: 'Детский',
    10765: 'Фантастика и фэнтези',
  };
  List<MediaItem> get catalog => const [];
  List<MediaItem> get trending => const [];
  List<MediaItem> search(String query, {String? type}) => const [];
  List<MediaItem> recommendedFor(UserPreferences preferences) => const [];
  Future<List<MediaItem>> searchOnline(String query, {String? type}) async {
    if (query.trim().isEmpty || !isConfigured) return const [];
    final endpoint = switch (type) {
      'Фильм' => 'movie',
      'Сериал' || 'Аниме' => 'tv',
      _ => 'multi',
    };
    final uri = Uri.parse('$_api/search/$endpoint').replace(
      queryParameters: {
        'query': query.trim(),
        'language': 'ru-RU',
        'include_adult': 'false',
        'page': '1',
      },
    );
    try {
      final response = await http
          .get(
            uri,
            headers: {'Authorization': '***', 'accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return const [];
      final json = jsonDecode(response.body);
      if (json is! Map<String, dynamic> || json['results'] is! List)
        return const [];
      final items = <MediaItem>[];
      for (final raw in json['results'] as List) {
        if (raw is! Map<String, dynamic>) continue;
        final kind = raw['media_type'] ?? endpoint;
        if (kind == 'person') continue;
        final tv = kind == 'tv';
        final lang = raw['original_language'] as String? ?? '';
        final countries = (raw['origin_country'] as List? ?? const [])
            .whereType<String>();
        final anime = tv && (lang == 'ja' || countries.contains('JP'));
        if ((type == 'Аниме' && !anime) || (type == 'Сериал' && anime))
          continue;
        final title = (raw[tv ? 'name' : 'title'] as String? ?? '').trim();
        final id = raw['id'];
        if (title.isEmpty || id == null) continue;
        final poster = raw['poster_path'] as String?;
        final ids = (raw['genre_ids'] as List? ?? const []).whereType<num>();
        items.add(
          MediaItem(
            id: 'tmdb:${tv ? 'tv' : 'movie'}:$id',
            title: title,
            type: anime
                ? 'Аниме'
                : tv
                ? 'Сериал'
                : 'Фильм',
            posterUrl: poster == null ? '' : '$_poster$poster',
            rating: (raw['vote_average'] as num?)?.toDouble() ?? 0,
            voiceovers: const [],
            videoUrl: '',
            categories: ids
                .map((g) => _genres[g.toInt()])
                .whereType<String>()
                .toList(),
            description: raw['overview'] as String? ?? '',
          ),
        );
      }
      return items;
    } on Object {
      return const [];
    }
  }

  Future<MediaDetails?> loadDetails(MediaItem item) async {
    if (!isConfigured || !item.id.startsWith('tmdb:')) return null;
    final p = item.id.split(':');
    if (p.length != 3 || !{'movie', 'tv'}.contains(p[1])) return null;
    final uri = Uri.parse('$_api/' + p[1] + '/' + p[2]).replace(
      queryParameters: {'language': 'ru-RU', 'append_to_response': 'credits'},
    );
    try {
      final r = await http
          .get(
            uri,
            headers: {'Authorization': '***', 'accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return null;
      final data = jsonDecode(r.body);
      if (data is! Map<String, dynamic>) return null;
      final credits = data['credits'] as Map<String, dynamic>? ?? const {};
      final cast = (credits['cast'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .take(12)
          .map(
            (x) => MediaCastMember(
              name: x['name'] as String? ?? '',
              character: x['character'] as String? ?? '',
              photoUrl: x['profile_path'] is String
                  ? 'https://image.tmdb.org/t/p/w185' +
                        (x['profile_path'] as String)
                  : '',
            ),
          )
          .where((x) => x.name.isNotEmpty)
          .toList();
      final genres = (data['genres'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((x) => x['name'])
          .whereType<String>()
          .toList();
      int? runtime;
      if (data['runtime'] is num)
        runtime = (data['runtime'] as num).toInt();
      else {
        for (final x in (data['episode_run_time'] as List? ?? const [])) {
          if (x is num) {
            runtime = x.toInt();
            break;
          }
        }
      }
      final b = data['backdrop_path'] as String?;
      return MediaDetails(
        overview: data['overview'] as String? ?? item.description,
        genres: genres.isEmpty ? item.categories : genres,
        cast: cast,
        runtimeMinutes: runtime,
        releaseDate:
            data['release_date'] as String? ??
            data['first_air_date'] as String? ??
            '',
        backdropUrl: b == null ? '' : 'https://image.tmdb.org/t/p/w1280$b',
        homepage: data['homepage'] as String? ?? '',
      );
    } on Object {
      return null;
    }
  }

  String? preferredVoiceover(MediaItem item, UserPreferences preferences) {
    for (final p in preferences.voiceDubbing) {
      for (final v in item.voiceovers) {
        if (v.toLowerCase() == p.trim().toLowerCase()) return v;
      }
    }
    return item.voiceovers.isEmpty ? null : item.voiceovers.first;
  }
}

class MediaDetails {
  const MediaDetails({
    required this.overview,
    required this.genres,
    required this.cast,
    required this.runtimeMinutes,
    required this.releaseDate,
    required this.backdropUrl,
    required this.homepage,
  });
  final String overview;
  final List<String> genres;
  final List<MediaCastMember> cast;
  final int? runtimeMinutes;
  final String releaseDate, backdropUrl, homepage;
}

class MediaCastMember {
  const MediaCastMember({
    required this.name,
    required this.character,
    required this.photoUrl,
  });
  final String name, character, photoUrl;
}
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum MediaSegmentType { intro, credits }

class MediaSegmentMarker {
  const MediaSegmentMarker({
    required this.type,
    required this.start,
    required this.end,
  });

  final MediaSegmentType type;
  final Duration start;
  final Duration end;

  bool get isValid => start >= Duration.zero && end > start;

  Map<String, Object> toJson() => {
    'type': type.name,
    'startMs': start.inMilliseconds,
    'endMs': end.inMilliseconds,
  };

  static MediaSegmentMarker? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final typeName = value['type'];
    final startMs = value['startMs'];
    final endMs = value['endMs'];
    if (typeName is! String || startMs is! int || endMs is! int) {
      return null;
    }
    final type = MediaSegmentType.values.where((item) => item.name == typeName);
    if (type.isEmpty) return null;
    final marker = MediaSegmentMarker(
      type: type.first,
      start: Duration(milliseconds: startMs),
      end: Duration(milliseconds: endMs),
    );
    return marker.isValid ? marker : null;
  }
}

abstract interface class MediaSegmentMarkerStore {
  Future<List<MediaSegmentMarker>> load(String mediaId, int episodeIndex);

  Future<void> save(
    String mediaId,
    int episodeIndex,
    List<MediaSegmentMarker> markers,
  );
}

class SharedPreferencesMediaSegmentMarkerStore
    implements MediaSegmentMarkerStore {
  SharedPreferencesMediaSegmentMarkerStore({SharedPreferencesAsync? store})
    : _store = store ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _store;

  String _key(String mediaId, int episodeIndex) =>
      'omni_ai.media_segments.v1.$mediaId.$episodeIndex';

  @override
  Future<List<MediaSegmentMarker>> load(
    String mediaId,
    int episodeIndex,
  ) async {
    try {
      final raw = await _store.getString(_key(mediaId, episodeIndex));
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .map(MediaSegmentMarker.fromJson)
          .whereType<MediaSegmentMarker>()
          .toList(growable: false);
    } on Object {
      return const [];
    }
  }

  @override
  Future<void> save(
    String mediaId,
    int episodeIndex,
    List<MediaSegmentMarker> markers,
  ) async {
    final valid = markers.where((marker) => marker.isValid).toList();
    try {
      await _store.setString(
        _key(mediaId, episodeIndex),
        jsonEncode(valid.map((marker) => marker.toJson()).toList()),
      );
    } on Object {
      // Marker storage must never interrupt playback.
    }
  }
}
