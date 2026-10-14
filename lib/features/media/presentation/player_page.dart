import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:omni_ai/features/media/data/media_item.dart';
import 'package:omni_ai/features/media/data/torrserver_playback_resolver.dart';
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
    this.searchService = const MediaSearchService(),
    this.playerFactory,
    this.torrServerResolver,
    this.resumePositionStore,
    this.segmentMarkerStore,
    this.aniSkipSegmentProvider,
    this.playbackSettingsStore,
    super.key,
  });

  final MediaItem item;
  final UserPreferences preferences;
  final MediaSearchService searchService;
  final MediaPlayerFactory? playerFactory;
  final TorrServerPlaybackResolver? torrServerResolver;
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
  int _selectedEpisode = 0;
  int _playerGeneration = 0;
  Timer? _progressTimer;
  final Set<int> _resumePromptedEpisodes = <int>{};
  final Set<int> _watchedEpisodes = <int>{};
  List<MediaSegmentMarker> _segmentMarkers = const [];
  List<MediaSegmentMarker> _remoteSegmentMarkers = const [];
  Set<String> _likedVoiceovers = <String>{};
  String? _selectedQuality;
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
      if (mounted) setState(() {});
    });
    _selectedVoiceover = widget.searchService.preferredVoiceover(
      widget.item,
      widget.preferences,
    );
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

  String _formatTorrentFileSize(int bytes) {
    const megabyte = 1024 * 1024;
    const gigabyte = 1024 * megabyte;
    if (bytes >= gigabyte) {
      return '${(bytes / gigabyte).toStringAsFixed(1)} ГБ';
    }
    if (bytes >= megabyte) {
      return '${(bytes / megabyte).toStringAsFixed(0)} МБ';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} КБ';
    }
    return '$bytes Б';
  }

  Future<int?> _chooseTorrServerFile(
    TorrServerFileSelectionRequired selection,
  ) {
    return showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ВЫБЕРИТЕ ВИДЕОФАЙЛ'),
        content: SizedBox(
          width: double.maxFinite,
          height: MediaQuery.sizeOf(dialogContext).height * 0.55,
          child: ListView.separated(
            itemCount: selection.files.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final file = selection.files[index];
              final normalizedPath = file.path.replaceAll(RegExp(r'\\'), '/');
              final parts = normalizedPath.split('/');
              final name = parts.isEmpty ? file.path : parts.last;
              return ListTile(
                title: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  '${file.path}\n${_formatTorrentFileSize(file.length)}',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => Navigator.of(dialogContext).pop(file.id),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('ОТМЕНА'),
          ),
        ],
      ),
    );
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
        : episode?.voiceoverVideoUrls[selectedVoiceover] ??
              widget.item.voiceoverVideoUrls[selectedVoiceover];
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
    final sources = <String>{
      source.trim(),
      ...fallbackUrls.map((url) => url.trim()),
    }.where((url) => url.isNotEmpty).toList(growable: false);
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

    Object? playerError;
    final playableSources = <String>[];
    var torrentFileSelectionCancelled = false;
    for (final candidate in sources) {
      final candidateUri = Uri.tryParse(candidate);
      if (candidateUri?.scheme.toLowerCase() != 'magnet') {
        playableSources.add(candidate);
        continue;
      }
      final endpoint = widget.preferences.torrServerUrl.trim();
      if (endpoint.isEmpty) {
        playerError = StateError(
          'Сначала укажите адрес TorrServer в сетевых настройках.',
        );
        continue;
      }

      final resolver =
          widget.torrServerResolver ?? TorrServerPlaybackResolver();
      try {
        Uri resolvedUri;
        try {
          resolvedUri = await resolver.resolve(
            endpoint: endpoint,
            magnetUri: candidateUri!,
            title: widget.item.title,
            episodeNumber: episode?.number,
            seasonNumber: episode?.seasonNumber,
          );
        } on TorrServerFileSelectionRequired catch (selection) {
          if (!mounted || generation != _playerGeneration) return;
          final selectedFileIndex = await _chooseTorrServerFile(selection);
          if (selectedFileIndex == null) {
            playerError = StateError('Выбор видеофайла отменён.');
            torrentFileSelectionCancelled = true;
            break;
          }
          if (!mounted || generation != _playerGeneration) return;
          resolvedUri = await resolver.resolve(
            endpoint: endpoint,
            magnetUri: candidateUri!,
            title: widget.item.title,
            episodeNumber: episode?.number,
            seasonNumber: episode?.seasonNumber,
            selectedFileIndex: selectedFileIndex,
            existingTorrentHash: selection.torrentHash,
          );
        }
        playableSources.add(resolvedUri.toString());
      } on Object catch (error) {
        playerError = error;
      } finally {
        if (widget.torrServerResolver == null) resolver.close();
      }
    }

    if (torrentFileSelectionCancelled) {
      if (!mounted || generation != _playerGeneration) return;
      setState(() {
        _playerError = playerError;
        _isLoading = false;
      });
      return;
    }

    for (var index = 0; index < playableSources.length; index++) {
      if (!mounted || generation != _playerGeneration) return;
      MediaPlaybackController? nextPlayer;
      try {
        nextPlayer = playerFactory(Uri.parse(playableSources[index]));
        await nextPlayer.initialize();
        if (!mounted || generation != _playerGeneration) {
          await _disposePlayer(nextPlayer);
          return;
        }
        setState(() {
          _player = nextPlayer;
          _isLoading = false;
          _playerError = null;
        });
        unawaited(_loadAniSkipMarkers(nextPlayer, episodeIndex, generation));
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
    final episodeNumber = _hasEpisodes
        ? widget.item.episodes[episodeIndex].number
        : episodeIndex + 1;
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
          if (episodes.map((episode) => episode.seasonNumber).toSet().length >
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
                    child: Text('СЕЗОН ${season.toString().padLeft(2, '0')}'),
                  ),
              ],
              onChanged: (season) {
                if (season == null) return;
                final firstEpisode = episodes.indexWhere(
                  (episode) => episode.seasonNumber == season,
                );
                if (firstEpisode >= 0 && firstEpisode != _selectedEpisode) {
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
                  onPressed: () => _toggleVoiceoverLike(_selectedVoiceover!),
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

  List<MediaVideoSource> _availableVideoSourcesFor(MediaEpisode? episode) {
    final episodeSources = episode?.videoSources ?? const <MediaVideoSource>[];
    return episodeSources.isNotEmpty
        ? episodeSources
        : widget.item.videoSources;
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

  Future<void> _selectQuality(String quality) async {
    if (quality == _selectedQuality) return;
    setState(() => _selectedQuality = quality);
    await _playbackSettingsStore.saveQuality(widget.item.id, quality);
    if (mounted) await _loadEpisode(_selectedEpisode);
  }

  List<String> _availableVoiceoversFor(MediaEpisode? episode) {
    final episodeSources =
        episode?.voiceoverVideoUrls ?? const <String, String>{};
    final sources = episodeSources.isNotEmpty
        ? episodeSources
        : widget.item.voiceoverVideoUrls;
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
