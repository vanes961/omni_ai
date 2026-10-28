import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:omni_ai/features/media/data/media_item.dart';
import 'package:omni_ai/features/media/data/video_source_engine.dart';
import 'package:omni_ai/features/media/data/video_source_provider.dart';
import 'package:omni_ai/features/media/services/ani_skip_segment_provider.dart';
import 'package:omni_ai/features/media/services/media_headers.dart';
import 'package:omni_ai/features/media/services/media_playback_settings_store.dart';
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
    this.searchService,
    this.playerFactory,
    this.videoSourceEngine,
    this.resumePositionStore,
    this.segmentMarkerStore,
    this.aniSkipSegmentProvider,
    this.playbackSettingsStore,
    super.key,
  });

  final MediaItem item;
  final UserPreferences preferences;
  final MediaSearchService? searchService;
  final MediaPlayerFactory? playerFactory;
  final VideoSourceEngine? videoSourceEngine;
  final MediaResumePositionStore? resumePositionStore;
  final MediaSegmentMarkerStore? segmentMarkerStore;
  final AniSkipSegmentProvider? aniSkipSegmentProvider;
  final MediaPlaybackSettingsStore? playbackSettingsStore;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> with WidgetsBindingObserver {
  late String? _selectedVoiceover;
  MediaPlaybackController? _player;
  Object? _playerError;
  bool _isLoading = true;
  bool _isFullscreen = false;
  int _selectedEpisode = 0;
  int _playerGeneration = 0;
  Timer? _progressTimer;
  Timer? _positionTimer;
  final Set<int> _resumePromptedEpisodes = <int>{};
  final Set<int> _watchedEpisodes = <int>{};
  List<MediaSegmentMarker> _segmentMarkers = const [];
  List<MediaSegmentMarker> _remoteSegmentMarkers = const [];
  Set<String> _likedVoiceovers = <String>{};
  String? _selectedQuality;
  Duration? _seekingPosition;
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

  AniSkipSegmentProvider get _aniSkipProvider =>
      widget.aniSkipSegmentProvider ?? AniSkipSegmentProvider();

  MediaPlaybackSettingsStore get _playbackSettingsStore =>
      widget.playbackSettingsStore ??
      SharedPreferencesMediaPlaybackSettingsStore();

  bool get _hasEpisodes => widget.item.episodes.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadWatchedHistory());
    unawaited(_loadLikedVoiceovers());
    _progressTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(_saveProgress());
    });
    // Refresh overlay controls more often than we persist progress so skip
    // buttons appear promptly when playback enters a marked segment.
    _positionTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted && (_player?.isInitialized ?? false)) {
        setState(() {});
      }
    });
    _selectedVoiceover = (widget.searchService ?? MediaSearchService())
        .preferredVoiceover(widget.item, widget.preferences);
    unawaited(_restoreVoiceoverAndLoadEpisode());
  }

  Future<void> _restoreVoiceoverAndLoadEpisode() async {
    final savedVoiceover = await _playbackSettingsStore.loadVoiceover(
      widget.item.id,
    );
    final savedQuality = await _playbackSettingsStore.loadQuality(
      widget.item.id,
    );
    if (mounted &&
        savedVoiceover != null &&
        widget.item.voiceovers.contains(savedVoiceover)) {
      _selectedVoiceover = savedVoiceover;
    }
    if (mounted) _selectedQuality = savedQuality;
    if (mounted) await _loadEpisode(0);
  }

  Future<void> _loadLikedVoiceovers() async {
    final liked = await _playbackSettingsStore.loadLikedVoiceovers();
    if (mounted) setState(() => _likedVoiceovers = liked);
  }

  Future<void> _toggleVoiceoverLike(String voiceover) async {
    final nowLiked = await _playbackSettingsStore.toggleVoiceoverLike(
      voiceover,
    );
    if (!mounted) return;
    setState(() {
      if (nowLiked) {
        _likedVoiceovers.add(voiceover);
      } else {
        _likedVoiceovers.remove(voiceover);
      }
    });
  }

  @override
  void dispose() {
    _playerGeneration++;
    if (_isFullscreen) unawaited(_restoreSystemUi());
    WidgetsBinding.instance.removeObserver(this);
    _progressTimer?.cancel();
    _positionTimer?.cancel();
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
      if (player.duration > Duration.zero &&
          remaining <= const Duration(seconds: 15) &&
          _tracksEpisodeHistory &&
          _hasEpisodes &&
          episodeIndex >= 0 &&
          episodeIndex < widget.item.episodes.length) {
        await _resumeStore.markEpisodeWatched(widget.item.id, episodeIndex);
        if (mounted && _watchedEpisodes.add(episodeIndex)) {
          setState(() {});
        }
      }
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
    final variants = _availableVideoSourcesFor(episode);
    final voiceoverVariants = variants
        .where((variant) => variant.voiceover == selectedVoiceover)
        .toList(growable: false);
    final matchingVariants = voiceoverVariants.isNotEmpty
        ? voiceoverVariants
        : variants.where((variant) => variant.voiceover == null).toList();
    final selectedVariant = matchingVariants.isEmpty
        ? null
        : matchingVariants.firstWhere(
            (variant) => variant.quality == _selectedQuality,
            orElse: () => matchingVariants.first,
          );
    final voiceoverSource = selectedVoiceover == null
        ? null
        : episode == null
        ? widget.item.voiceoverVideoUrls[selectedVoiceover]
        : episode.voiceoverVideoUrls[selectedVoiceover];
    final source = selectedVariant?.url ?? voiceoverSource ?? defaultSource;
    final fallbackUrls = [
      ...matchingVariants
          .where((variant) => variant.url != source)
          .map((variant) => variant.url),
      if (voiceoverSource != null) defaultSource,
      if (episode == null) ...widget.item.videoFallbackUrls,
      if (episode != null) ...episode.videoFallbackUrls,
    ];
    if (selectedVariant != null &&
        _selectedQuality != selectedVariant.quality) {
      _selectedQuality = selectedVariant.quality;
      unawaited(
        _playbackSettingsStore.saveQuality(
          widget.item.id,
          selectedVariant.quality,
        ),
      );
    }
    Object? playerError;
    var sources = <String>{
      source.trim(),
      ...fallbackUrls.map((url) => url.trim()),
    }.where((url) => url.isNotEmpty).toList(growable: false);

    // Catalog metadata is not a video stream. Ask configured playback
    // providers only when the item has no direct/fallback stream URL.
    final sourceEngine = widget.videoSourceEngine;
    if (sources.isEmpty && sourceEngine != null) {
      final type = widget.item.type.toLowerCase();
      final kind = type.contains('аниме') || type.contains('anime')
          ? PlaybackMediaKind.anime
          : type.contains('сериал') ||
                type.contains('series') ||
                type.contains('сезон')
          ? PlaybackMediaKind.series
          : PlaybackMediaKind.movie;
      try {
        final resolution = await sourceEngine.resolve(
          PlaybackRequest(
            mediaId: widget.item.id,
            title: widget.item.title,
            kind: kind,
            season: episode?.seasonNumber,
            episode: episode?.number,
          ),
        );
        if (!mounted || generation != _playerGeneration) return;
        final resolvedVariants = resolution.variants.toList();
        // Prefer the user's saved voiceover and quality, then try the other
        // real variants in provider order as playback fallbacks.
        resolvedVariants.sort((a, b) {
          int score(PlaybackVariant value) {
            var result = 0;
            if (_selectedVoiceover != null &&
                value.voiceover == _selectedVoiceover) {
              result += 2;
            }
            if (_selectedQuality != null && value.quality == _selectedQuality) {
              result += 1;
            }
            return result;
          }

          return score(b).compareTo(score(a));
        });
        sources = resolvedVariants
            .map((variant) => variant.url.trim())
            .where((url) => url.isNotEmpty)
            .toSet()
            .toList(growable: false);
        if (sources.isEmpty) {
          playerError = StateError(
            resolution.message ?? 'Не найден доступный видеопоток.',
          );
        }
      } on Object catch (error) {
        playerError = error;
      }
    }
    final playerFactory = widget.playerFactory ?? _videoPlayerFactory;

    unawaited(_saveProgress(player: oldPlayer, episodeIndex: _selectedEpisode));
    setState(() {
      _selectedEpisode = episodeIndex;
      _segmentMarkers = const [];
      _remoteSegmentMarkers = const [];
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

    final playableSources = <String>[];
    for (final candidate in sources) {
      final candidateUri = Uri.tryParse(candidate);
      if (candidateUri?.scheme.toLowerCase() == 'magnet') {
        playerError = StateError(
          'Встроенный торрент-движок OMNI AI пока не подключён.',
        );
        continue;
      }
      playableSources.add(candidate);
    }

    Future<bool> tryPlaybackSource(String source) async {
      if (!mounted || generation != _playerGeneration) return false;
      MediaPlaybackController? nextPlayer;
      try {
        nextPlayer = playerFactory(Uri.parse(source));
        await nextPlayer.initialize();
        if (!mounted || generation != _playerGeneration) {
          await _disposePlayer(nextPlayer);
          return false;
        }
        setState(() {
          _player = nextPlayer;
          _isLoading = false;
          _playerError = null;
        });
        unawaited(_loadAniSkipMarkers(nextPlayer, episodeIndex, generation));
        await _offerResumeIfAvailable(nextPlayer, episodeIndex, generation);
        return true;
      } on PlatformException catch (error) {
        playerError = error;
        await _disposePlayer(nextPlayer);
        return false;
      } on Object catch (error) {
        playerError = error;
        await _disposePlayer(nextPlayer);
        return false;
      }
    }

    // First try the selected catalog URL and its known alternates.
    for (final candidate in playableSources) {
      if (await tryPlaybackSource(candidate)) return;
      if (!mounted || generation != _playerGeneration) return;
    }

    // If every catalog URL failed, ask OMNI's own source engine for fresh
    // alternatives. TorrServer is not required for HTTP/HLS/DASH providers.
    // Magnet variants are deliberately not passed to video_player: they need
    // the native torrent bridge, which is a separate integration step.
    if (sourceEngine != null) {
      sourceEngine.clearCache();
      final type = widget.item.type.toLowerCase();
      final kind = type.contains('аниме') || type.contains('anime')
          ? PlaybackMediaKind.anime
          : type.contains('сериал') ||
                type.contains('series') ||
                type.contains('сезон')
          ? PlaybackMediaKind.series
          : PlaybackMediaKind.movie;
      try {
        final fallbackResolution = await sourceEngine.resolve(
          PlaybackRequest(
            mediaId: widget.item.id,
            title: widget.item.title,
            kind: kind,
            season: episode?.seasonNumber,
            episode: episode?.number,
          ),
        );
        if (!mounted || generation != _playerGeneration) return;
        final attempted = playableSources.toSet();
        final fallbackVariants =
            fallbackResolution.variants
                .where((variant) => variant.isHttpStream)
                .toList(growable: false)
              ..sort((a, b) {
                int score(PlaybackVariant value) {
                  var result = 0;
                  if (_selectedVoiceover != null &&
                      value.voiceover == _selectedVoiceover) {
                    result += 2;
                  }
                  if (_selectedQuality != null &&
                      value.quality == _selectedQuality) {
                    result += 1;
                  }
                  return result;
                }

                return score(b).compareTo(score(a));
              });
        for (final variant in fallbackVariants) {
          final candidate = variant.url.trim();
          if (candidate.isEmpty || !attempted.add(candidate)) continue;
          if (await tryPlaybackSource(candidate)) return;
          if (!mounted || generation != _playerGeneration) return;
        }
      } on Object catch (error) {
        playerError = error;
      }
    }

    if (!mounted || generation != _playerGeneration) return;
    setState(() {
      _playerError =
          playerError ??
          StateError('Не удалось запустить ни один найденный источник.');
      _isLoading = false;
    });
  }

  Future<void> _loadAniSkipMarkers(
    MediaPlaybackController player,
    int episodeIndex,
    int generation,
  ) async {
    final malId = widget.item.malId;
    if (malId == null ||
        !_tracksAnime ||
        !player.isInitialized ||
        player.duration <= Duration.zero) {
      return;
    }
    // AniSkip uses absolute episode numbering across seasons. MediaEpisode.number
    // is season-local in many catalogs, so use the ordered list index instead.
    final episodeNumber = episodeIndex + 1;
    final markers = await _aniSkipProvider.load(
      malId: malId,
      episodeNumber: episodeNumber,
      episodeDuration: player.duration,
    );
    if (!mounted ||
        generation != _playerGeneration ||
        !identical(_player, player)) {
      return;
    }
    setState(() => _remoteSegmentMarkers = markers);
  }

  bool get _tracksAnime {
    final type = widget.item.type.toLowerCase();
    return type.contains('аниме') || type.contains('anime');
  }

  MediaSegmentMarker? _activeMarker(
    MediaSegmentType type,
    MediaPlaybackController player,
  ) {
    final localMarkers = _segmentMarkers
        .where((marker) => marker.type == type)
        .toList(growable: false);
    final markers = localMarkers.isNotEmpty
        ? localMarkers
        : _remoteSegmentMarkers.where((marker) => marker.type == type);
    for (final marker in markers) {
      if (player.position >= marker.start && player.position < marker.end) {
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
    final duration = player.duration;
    final boundedPosition = duration > Duration.zero
        ? Duration(
            milliseconds: position.inMilliseconds
                .clamp(0, duration.inMilliseconds)
                .toInt(),
          )
        : Duration(
            milliseconds: position.inMilliseconds.clamp(0, 0x7fffffff).toInt(),
          );
    try {
      await player.seekTo(boundedPosition);
      if (mounted && identical(_player, player)) {
        setState(() => _playerError = null);
      }
    } on Object catch (error) {
      if (mounted && identical(_player, player)) {
        setState(() => _playerError = error);
      }
    }
  }

  Future<void> _finishSeek(
    MediaPlaybackController player,
    double milliseconds,
  ) async {
    await _seekTo(player, Duration(milliseconds: milliseconds.round()));
    if (mounted) setState(() => _seekingPosition = null);
  }

  Future<void> _seekBy(MediaPlaybackController player, Duration offset) =>
      _seekTo(player, player.position + offset);

  Future<void> _toggleFullscreen() async {
    final enable = !_isFullscreen;
    if (mounted) setState(() => _isFullscreen = enable);
    try {
      await SystemChrome.setEnabledSystemUIMode(
        enable ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      );
      await SystemChrome.setPreferredOrientations(
        enable
            ? const [
                DeviceOrientation.landscapeLeft,
                DeviceOrientation.landscapeRight,
              ]
            : const [],
      );
    } on Object {
      // Keep the in-app fullscreen layout usable if a platform rejects the
      // orientation or system-UI request (for example, in widget tests).
    }
  }

  Future<void> _restoreSystemUi() async {
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations(const []);
    } on Object {
      // Restoring platform UI must not block widget disposal.
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

  String _playerErrorDescription(Object? error) {
    if (error == null) {
      return 'Источник не удалось открыть. Повтори запуск и проверь диагностику.';
    }
    final message = error.toString().toLowerCase();
    if (message.contains('выбор видеофайла отменён')) {
      return 'Выбор видеофайла отменён. Выбери файл и повтори запуск.';
    }
    if (message.contains('timeout') || message.contains('timed out')) {
      return 'Источник не ответил вовремя. Проверь соединение и доступность источника.';
    }
    if (error is PlatformException) {
      return 'Медиаплеер платформы не смог открыть поток. Возможна неподдерживаемая кодировка или ошибка источника.';
    }
    if (message.contains('http 401') || message.contains('http 403')) {
      return 'Источник отклонил запрос. Проверь доступность и права на поток.';
    }
    if (message.contains('format') || message.contains('codec')) {
      return 'Формат или кодек потока может не поддерживаться текущим плеером.';
    }
    return 'Не удалось открыть источник. Тип ошибки: ${error.runtimeType}. Проверь источник и повтори запуск.';
  }

  @override
  Widget build(BuildContext context) {
    final episodes = widget.item.episodes;

    return Scaffold(
      backgroundColor: SystemCorePalette.background,
      appBar: _isFullscreen
          ? null
          : AppBar(
              title: const Text('OMNI // PLAYER'),
              backgroundColor: SystemCorePalette.background,
            ),
      body: _isFullscreen
          ? Center(child: _buildPlayerSurface())
          : ListView(
              key: const ValueKey('player-page-scroll'),
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
                if (episodes.isNotEmpty) ...[
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
                if (episodes
                        .map((episode) => episode.seasonNumber)
                        .toSet()
                        .length >
                    1) ...[
                  const _PlayerSectionLabel('ВЫБОР СЕЗОНА'),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    key: const ValueKey('season-selector'),
                    initialValue: episodes[_selectedEpisode].seasonNumber,
                    isExpanded: true,
                    dropdownColor: SystemCorePalette.panel,
                    decoration: _selectorDecoration(),
                    items: [
                      for (final season
                          in (episodes
                              .map((episode) => episode.seasonNumber)
                              .toSet()
                              .toList()
                            ..sort()))
                        DropdownMenuItem(
                          value: season,
                          child: Text(
                            'СЕЗОН ${season.toString().padLeft(2, '0')}',
                          ),
                        ),
                    ],
                    onChanged: (season) {
                      if (season == null) return;
                      final firstEpisode = episodes.indexWhere(
                        (episode) => episode.seasonNumber == season,
                      );
                      if (firstEpisode >= 0 &&
                          firstEpisode != _selectedEpisode) {
                        _loadEpisode(firstEpisode);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                if (episodes
                        .where(
                          (episode) =>
                              episode.seasonNumber ==
                              episodes[_selectedEpisode].seasonNumber,
                        )
                        .length >
                    1) ...[
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
                        if (episodes[index].seasonNumber ==
                            episodes[_selectedEpisode].seasonNumber)
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
                      final availableVoiceovers = _availableVoiceoversFor(
                        episode,
                      );
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
                        initialValue:
                            availableVoiceovers.contains(_selectedVoiceover)
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
                          if (voiceover == null ||
                              voiceover == _selectedVoiceover) {
                            return;
                          }
                          setState(() => _selectedVoiceover = voiceover);
                          unawaited(
                            _playbackSettingsStore.saveVoiceover(
                              widget.item.id,
                              voiceover,
                            ),
                          );
                          _loadEpisode(_selectedEpisode);
                        },
                      );
                    },
                  ),
                  if (_selectedVoiceover != null &&
                      _availableVoiceoversFor(
                        _hasEpisodes ? episodes[_selectedEpisode] : null,
                      ).contains(_selectedVoiceover))
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        key: const ValueKey('voiceover-like-button'),
                        onPressed: () =>
                            _toggleVoiceoverLike(_selectedVoiceover!),
                        icon: Icon(
                          _likedVoiceovers.contains(_selectedVoiceover)
                              ? Icons.thumb_up
                              : Icons.thumb_up_outlined,
                          size: 18,
                        ),
                        label: Text(
                          _likedVoiceovers.contains(_selectedVoiceover)
                              ? 'Озвучка нравится'
                              : 'Нравится эта озвучка',
                        ),
                      ),
                    ),
                ],
                if (_availableQualitiesFor(
                  _hasEpisodes ? episodes[_selectedEpisode] : null,
                ).isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const _PlayerSectionLabel('КАЧЕСТВО ВИДЕО'),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    key: const ValueKey('quality-selector'),
                    initialValue:
                        _availableQualitiesFor(
                          _hasEpisodes ? episodes[_selectedEpisode] : null,
                        ).contains(_selectedQuality)
                        ? _selectedQuality
                        : _availableQualitiesFor(
                            _hasEpisodes ? episodes[_selectedEpisode] : null,
                          ).first,
                    isExpanded: true,
                    dropdownColor: SystemCorePalette.panel,
                    decoration: _selectorDecoration(),
                    items: [
                      for (final quality in _availableQualitiesFor(
                        _hasEpisodes ? episodes[_selectedEpisode] : null,
                      ))
                        DropdownMenuItem(value: quality, child: Text(quality)),
                    ],
                    onChanged: (quality) {
                      if (quality != null) unawaited(_selectQuality(quality));
                    },
                  ),
                ],
              ],
            ),
    );
  }

  Widget _buildPlayerSurface() {
    final player = _player;
    final displayedPosition =
        _seekingPosition ?? player?.position ?? Duration.zero;
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
                        'НЕ УДАЛОСЬ ЗАПУСТИТЬ ВИДЕО',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                        ),
                      ),
                      if (_playerError != null) ...[
                        const SizedBox(height: 5),
                        Text(
                          _playerErrorDescription(_playerError),
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
                      _playerErrorDescription(_playerError),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ),
                ),
              ),
            if (player != null && player.isInitialized)
              Positioned(
                top: 8,
                left: 8,
                child: IconButton(
                  key: const ValueKey('fullscreen-toggle'),
                  tooltip: _isFullscreen
                      ? 'Выйти из полноэкранного режима'
                      : 'Полноэкранный режим',
                  visualDensity: VisualDensity.compact,
                  onPressed: _toggleFullscreen,
                  icon: Icon(
                    _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                    size: 22,
                  ),
                  color: Colors.white,
                ),
              ),
            if (player != null && player.isInitialized) ...[
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
                  bottom: 100,
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
                  color: Colors.black87,
                  padding: const EdgeInsets.fromLTRB(8, 2, 8, 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Slider(
                        key: const ValueKey('playback-progress-slider'),
                        min: 0,
                        max: player.duration.inMilliseconds > 0
                            ? player.duration.inMilliseconds.toDouble()
                            : 1,
                        value: displayedPosition.inMilliseconds
                            .clamp(
                              0,
                              player.duration.inMilliseconds > 0
                                  ? player.duration.inMilliseconds
                                  : 1,
                            )
                            .toDouble(),
                        activeColor: SystemCorePalette.green,
                        inactiveColor: Colors.white24,
                        onChanged: player.duration > Duration.zero
                            ? (value) => setState(() {
                                _seekingPosition = Duration(
                                  milliseconds: value.round(),
                                );
                              })
                            : null,
                        onChangeEnd: player.duration > Duration.zero
                            ? (value) => _finishSeek(player, value)
                            : null,
                      ),
                      Row(
                        children: [
                          Text(
                            _formatPosition(displayedPosition),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            key: const ValueKey('seek-back-10'),
                            tooltip: 'Назад на 10 секунд',
                            visualDensity: VisualDensity.compact,
                            onPressed: () =>
                                _seekBy(player, const Duration(seconds: -10)),
                            icon: const Icon(Icons.replay_10, size: 22),
                            color: Colors.white,
                          ),
                          IconButton(
                            tooltip: player.isPlaying
                                ? 'Пауза'
                                : 'Воспроизвести',
                            onPressed: () => _togglePlayback(player),
                            icon: Icon(
                              player.isPlaying ? Icons.pause : Icons.play_arrow,
                            ),
                            color: Colors.white,
                          ),
                          IconButton(
                            key: const ValueKey('seek-forward-10'),
                            tooltip: 'Вперёд на 10 секунд',
                            visualDensity: VisualDensity.compact,
                            onPressed: () =>
                                _seekBy(player, const Duration(seconds: 10)),
                            icon: const Icon(Icons.forward_10, size: 22),
                            color: Colors.white,
                          ),
                          if (_availableVoiceoversFor(
                            _hasEpisodes
                                ? widget.item.episodes[_selectedEpisode]
                                : null,
                          ).isNotEmpty)
                            PopupMenuButton<String>(
                              key: const ValueKey('in-player-voiceover-menu'),
                              tooltip: 'Озвучка',
                              initialValue: _selectedVoiceover,
                              color: SystemCorePalette.panel,
                              icon: const Icon(
                                Icons.audiotrack,
                                color: Colors.white,
                                size: 21,
                              ),
                              onSelected: (voiceover) =>
                                  unawaited(_selectVoiceover(voiceover)),
                              itemBuilder: (context) => [
                                for (final voiceover in _availableVoiceoversFor(
                                  _hasEpisodes
                                      ? widget.item.episodes[_selectedEpisode]
                                      : null,
                                ))
                                  PopupMenuItem<String>(
                                    value: voiceover,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (voiceover == _selectedVoiceover)
                                          const Icon(
                                            Icons.check,
                                            size: 16,
                                            color: SystemCorePalette.green,
                                          ),
                                        if (voiceover == _selectedVoiceover)
                                          const SizedBox(width: 6),
                                        Text(voiceover),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          if (_availableQualitiesFor(
                            _hasEpisodes
                                ? widget.item.episodes[_selectedEpisode]
                                : null,
                          ).isNotEmpty)
                            PopupMenuButton<String>(
                              key: const ValueKey('in-player-quality-menu'),
                              tooltip: 'Качество видео',
                              initialValue: _selectedQuality,
                              color: SystemCorePalette.panel,
                              icon: const Icon(
                                Icons.hd,
                                color: Colors.white,
                                size: 21,
                              ),
                              onSelected: (quality) =>
                                  unawaited(_selectQuality(quality)),
                              itemBuilder: (context) => [
                                for (final quality in _availableQualitiesFor(
                                  _hasEpisodes
                                      ? widget.item.episodes[_selectedEpisode]
                                      : null,
                                ))
                                  PopupMenuItem<String>(
                                    value: quality,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (quality == _selectedQuality)
                                          const Icon(
                                            Icons.check,
                                            size: 16,
                                            color: SystemCorePalette.green,
                                          ),
                                        if (quality == _selectedQuality)
                                          const SizedBox(width: 6),
                                        Text(quality),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          const Spacer(),
                          Text(
                            _formatPosition(player.duration),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<MediaVideoSource> _availableVideoSourcesFor(MediaEpisode? episode) {
    return episode == null ? widget.item.videoSources : episode.videoSources;
  }

  List<String> _availableQualitiesFor(MediaEpisode? episode) {
    final sources = _availableVideoSourcesFor(episode);
    final voiceover = _selectedVoiceover;
    final matching = sources.where((source) => source.voiceover == voiceover);
    final candidates = matching.isNotEmpty
        ? matching
        : sources.where((source) => source.voiceover == null);
    final qualities = <String>[];
    for (final source in candidates) {
      final quality = source.quality.trim();
      if (quality.isNotEmpty && !qualities.contains(quality)) {
        qualities.add(quality);
      }
    }
    return qualities;
  }

  Future<void> _selectVoiceover(String voiceover) async {
    if (voiceover == _selectedVoiceover) return;
    setState(() => _selectedVoiceover = voiceover);
    await _playbackSettingsStore.saveVoiceover(widget.item.id, voiceover);
    if (mounted) await _loadEpisode(_selectedEpisode);
  }

  Future<void> _selectQuality(String quality) async {
    if (quality == _selectedQuality) return;
    setState(() => _selectedQuality = quality);
    await _playbackSettingsStore.saveQuality(widget.item.id, quality);
    if (mounted) await _loadEpisode(_selectedEpisode);
  }

  List<String> _availableVoiceoversFor(MediaEpisode? episode) {
    final sources = episode == null
        ? widget.item.voiceoverVideoUrls
        : episode.voiceoverVideoUrls;
    final variants = _availableVideoSourcesFor(episode);
    return [
      for (final voiceover in widget.item.voiceovers)
        if ((sources.containsKey(voiceover) &&
                sources[voiceover]!.trim().isNotEmpty) ||
            variants.any(
              (source) =>
                  source.voiceover == voiceover && source.url.trim().isNotEmpty,
            ))
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