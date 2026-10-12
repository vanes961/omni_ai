import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:omni_ai/core/ai_engine/services/ai_engine.dart';
import 'package:omni_ai/core/ai_engine/models/ai_request.dart';
import 'package:omni_ai/core/diagnostics/diagnostic_report.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:omni_ai/features/news/data/news_interest_repository.dart';
import 'package:omni_ai/features/news/data/shared_preferences_news_cache.dart';
import 'package:omni_ai/features/news/data/news_feedback_repository.dart';
import 'package:omni_ai/features/news/data/shared_preferences_news_interest_repository.dart';
import 'package:omni_ai/features/news/models/news_interest_profile.dart';
import 'package:omni_ai/features/news/models/news_article.dart';
import 'package:omni_ai/features/favorites/data/favorite_item.dart';
import 'package:omni_ai/features/favorites/data/favorites_repository.dart';
import 'package:omni_ai/features/favorites/data/interest_feedback_repository.dart';
import 'package:omni_ai/features/favorites/services/favorite_interest_analytics.dart';
import 'package:omni_ai/features/news/services/news_rss_service.dart';
import 'package:omni_ai/features/news/services/news_digest_service.dart';
import 'package:omni_ai/features/news/services/news_source_localization_service.dart';
import 'package:omni_ai/features/news/services/news_reminder_service.dart';
import 'package:omni_ai/features/system_core/presentation/system_core_palette.dart';

class NewsCenterPage extends StatefulWidget {
  const NewsCenterPage({
    super.key,
    this.repository,
    this.aiEngine,
    this.newsService,
  });

  final NewsInterestRepository? repository;
  final AIEngine? aiEngine;
  final NewsRssService? newsService;

  @override
  State<NewsCenterPage> createState() => _NewsCenterPageState();
}

class _NewsCenterPageState extends State<NewsCenterPage> {
  late final NewsInterestRepository _repository;
  late final bool _ownsRepository;
  late Future<NewsInterestProfile> _profileFuture;
  NewsInterestProfile? _profile;
  bool _saving = false;
  String? _status;
  late final NewsRssService _newsService;
  final TextEditingController _customTopicController = TextEditingController();
  final FavoritesRepository _favoritesRepository = FavoritesRepository();
  final InterestFeedbackRepository _feedbackRepository =
      InterestFeedbackRepository();
  Set<String> _lessInterested = <String>{};
  final FavoriteInterestAnalytics _favoriteAnalytics =
      const FavoriteInterestAnalytics();
  NewsSourceLocalizationService get _sourceLocalizationService =>
      NewsSourceLocalizationService(aiEngine: widget.aiEngine);
  final SharedPreferencesNewsCache _newsCache = SharedPreferencesNewsCache();
  final NewsFeedbackRepository _newsFeedback = NewsFeedbackRepository();
  Map<String, double> _reactionWeights = const <String, double>{};
  bool _loadingNewsCache = true;
  int _interestRevision = 0;
  List<NewsArticle> _articles = const [];
  bool _showingCachedNews = false;
  bool _refreshingNews = false;
  bool _hasCompletedNewsFetch = false;
  bool _refreshPendingAfterCurrent = false;
  int? _lastRssCandidateCount;
  int? _lastLocalizedCandidateCount;
  int? _lastRankedCandidateCount;
  String? _newsError;
  bool _generatingDigest = false;
  String? _digest;
  String? _digestError;
  final NewsReminderService _reminderService = NewsReminderService();
  bool _morningReminder = false;
  bool _eveningReminder = false;
  bool _loadingReminderSettings = true;
  bool _updatingReminder = false;
  final GlobalKey _interestsSectionKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _ownsRepository = widget.repository == null;
    _repository =
        widget.repository ?? SharedPreferencesNewsInterestRepository();
    _newsService = widget.newsService ?? NewsRssService();
    _profileFuture = _repository.load();
    unawaited(_loadReactionWeights());
    unawaited(_loadReminderSettings());
    unawaited(_loadNewsCache());
  }

  @override
  void dispose() {
    if (_ownsRepository) unawaited(_repository.dispose());
    _newsService.dispose();
    _customTopicController.dispose();
    super.dispose();
  }

  Future<void> _loadNewsCache() async {
    final revisionAtStart = _interestRevision;
    NewsInterestProfile? loadedProfile;
    try {
      final profile = await _profileFuture;
      loadedProfile = profile;
      if (!mounted) return;
      setState(() => _profile ??= profile);
      final cached = await Future.wait<Object?>([
        _newsCache.loadArticles(),
        _newsCache.loadDigest(),
        _newsCache.loadTopics(),
        _newsCache.loadIncludeCriticalOutsideInterests(),
      ]);
      final savedTopics = cached[2] as List<String>?;
      final savedCriticalSetting = cached[3] as bool?;
      final favorites = await _favoritesRepository.getAll();
      _lessInterested = await _feedbackRepository.loadLessInterested();
      final favoriteProfile = _favoriteAnalytics.analyze(favorites);
      final cachedArticles = _rankByReaction(
        _favoriteAnalytics.rankNews(
          (cached[0] as List<NewsArticle>),
          favoriteProfile,
          lessInterested: _lessInterested,
        ),
      );
      final selectedTopics = _normalizeTopics(profile.topics);
      final cacheMatchesProfile =
          savedTopics != null &&
          savedCriticalSetting == profile.includeCriticalOutsideInterests &&
          _sameTopics(savedTopics, selectedTopics);
      if (!cacheMatchesProfile) {
        await _newsCache.clear();
      }
      if (!mounted) return;
      setState(() {
        if (revisionAtStart == _interestRevision && cacheMatchesProfile) {
          _articles = cachedArticles;
          _digest = cached[1] as String?;
          _showingCachedNews = cachedArticles.isNotEmpty;
        }
        _loadingNewsCache = false;
      });
      // When no valid cached feed exists, load the selected topics on entry
      // instead of leaving a blank screen until the user discovers Refresh.
      final hasFeedInterests =
          (_profile?.topics.isNotEmpty ?? false) ||
          (_profile?.includeCriticalOutsideInterests ?? false);
      if (hasFeedInterests && _articles.isEmpty) {
        unawaited(_refreshNews());
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingNewsCache = false);
      // Cache restoration is best-effort. If storage is unavailable or the
      // cached payload cannot be read, still attempt a fresh feed rather than
      // leaving users with a blank screen until they manually tap Refresh.
      final activeProfile = loadedProfile ?? _profile;
      final hasFeedInterests =
          (activeProfile?.topics.isNotEmpty ?? false) ||
          (activeProfile?.includeCriticalOutsideInterests ?? false);
      if (hasFeedInterests && _articles.isEmpty) {
        unawaited(_refreshNews());
      }
    }
  }

  List<String> _normalizeTopics(List<String> topics) {
    final normalized = topics
        .map((topic) => topic.trim().toLowerCase())
        .where((topic) => topic.isNotEmpty)
        .toSet()
        .toList();
    normalized.sort();
    return normalized;
  }

  bool _sameTopics(List<String> first, List<String> second) {
    final normalizedFirst = _normalizeTopics(first);
    final normalizedSecond = _normalizeTopics(second);
    if (normalizedFirst.length != normalizedSecond.length) return false;
    for (var i = 0; i < normalizedFirst.length; i++) {
      if (normalizedFirst[i] != normalizedSecond[i]) return false;
    }
    return true;
  }

  Future<void> _runDiagnostics() async {
    final report = DiagnosticReport(
      createdAt: DateTime.now(),
      checks: [
        DiagnosticCheck(
          name: 'Профиль интересов',
          status: _profile == null
              ? DiagnosticStatus.warning
              : (_profile!.topics.isEmpty
                    ? DiagnosticStatus.warning
                    : DiagnosticStatus.ok),
          details: _profile == null
              ? 'Профиль ещё не загружен'
              : 'Выбрано тем: ${_profile!.topics.length}',
        ),
        DiagnosticCheck(
          name: 'Новостная лента',
          status: _newsError != null
              ? DiagnosticStatus.error
              : (_refreshingNews
                    ? DiagnosticStatus.warning
                    : (_articles.isEmpty
                          ? DiagnosticStatus.warning
                          : DiagnosticStatus.ok)),
          details:
              _newsError ??
              'RSS-кандидатов: ${_lastRssCandidateCount ?? 'нет данных'}; '
                  'после локализации: ${_lastLocalizedCandidateCount ?? 'нет данных'}; '
                  'после персонализации: ${_lastRankedCandidateCount ?? 'нет данных'}; '
                  'на экране: ${_articles.length}'
                  '${_refreshingNews ? '; загрузка ещё выполняется' : ''}',
        ),
        DiagnosticCheck(
          name: 'Локальный кэш',
          status: _loadingNewsCache
              ? DiagnosticStatus.warning
              : DiagnosticStatus.ok,
          details: _loadingNewsCache
              ? 'Восстановление кэша ещё выполняется'
              : 'Загрузка кэша завершена',
        ),
        DiagnosticCheck(
          name: 'Реакции и интересы',
          status: DiagnosticStatus.ok,
          details:
              'Сигналов интереса: ${_reactionWeights.length}; значения хранятся локально',
        ),
        const DiagnosticCheck(
          name: 'Сетевая доступность',
          status: DiagnosticStatus.notChecked,
          details:
              'Проверяется только по результату загрузки ленты; отдельный сетевой тест не запускался',
        ),
      ],
    );
    final reportText = report.toPlainText();
    String? aiAnalysis;
    final engine = widget.aiEngine;
    if (engine != null) {
      try {
        final response = await engine.execute(
          AIRequest(
            id: 'diagnostic-${DateTime.now().microsecondsSinceEpoch}',
            systemInstruction: diagnosticAnalysisInstruction,
            prompt:
                'Проанализируй отчёт OMNI AI. Укажи факты, гипотезы и следующие проверки.\n\n$reportText',
            metadata: const {'feature': 'diagnostics'},
          ),
        );
        aiAnalysis = response.text;
      } catch (_) {
        aiAnalysis =
            'ИИ-анализ недоступен. Сам диагностический отчёт сформирован локально.';
      }
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: SystemCorePalette.panel,
        title: const Text('Диагностика OMNI AI'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              '$reportText${aiAnalysis == null ? '' : '\n\nАНАЛИЗ ИИ\n$aiAnalysis'}',
              style: const TextStyle(color: Colors.white70, height: 1.45),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('ЗАКРЫТЬ'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadReactionWeights() async {
    try {
      final weights = await _newsFeedback.interestWeights();
      if (!mounted) return;
      setState(() {
        _reactionWeights = weights;
        _articles = _rankByReaction(_articles);
      });
    } catch (_) {
      // Personalization is optional; the feed must still work without storage.
    }
  }

  List<NewsArticle> _rankByReaction(List<NewsArticle> articles) {
    if (_reactionWeights.isEmpty || articles.length < 2) return articles;
    final indexed = articles.indexed.toList();
    double score(NewsArticle article) => article.topics.fold<double>(
      0,
      (total, topic) =>
          total + (_reactionWeights[topic.trim().toLowerCase()] ?? 0),
    );
    indexed.sort((a, b) {
      final byScore = score(b.$2).compareTo(score(a.$2));
      return byScore != 0 ? byScore : a.$1.compareTo(b.$1);
    });
    return List<NewsArticle>.unmodifiable(indexed.map((entry) => entry.$2));
  }

  Future<void> _reactToArticle(
    NewsArticle article,
    NewsReaction reaction,
  ) async {
    try {
      await _newsFeedback.record(
        articleId: article.id,
        reaction: reaction,
        topics: article.topics,
      );
      final weights = await _newsFeedback.interestWeights();
      if (!mounted) return;
      setState(() {
        _reactionWeights = weights;
        _articles = _rankByReaction(_articles);
        _status = switch (reaction) {
          NewsReaction.like =>
            'Лайк сохранён: интересы будут учтены в рекомендациях.',
          NewsReaction.dislike =>
            'Учтено: похожие материалы будут показываться реже.',
          NewsReaction.opened => 'Просмотр учтён как слабый сигнал интереса.',
        };
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _status =
              'Не удалось сохранить реакцию. Лента продолжит работать.',
        );
      }
    }
  }

  Future<void> _loadReminderSettings() async {
    try {
      final settings = await _reminderService.loadSettings();
      if (!mounted) return;
      setState(() {
        _morningReminder = settings.morning;
        _eveningReminder = settings.evening;
        _loadingReminderSettings = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingReminderSettings = false);
    }
  }

  Future<void> _setReminder({
    required bool morning,
    required bool enabled,
  }) async {
    if (_updatingReminder) return;
    setState(() => _updatingReminder = true);
    try {
      final saved = morning
          ? await _reminderService.setMorningEnabled(enabled)
          : await _reminderService.setEveningEnabled(enabled);
      if (!mounted) return;
      setState(() {
        if (saved) {
          if (morning) {
            _morningReminder = enabled;
          } else {
            _eveningReminder = enabled;
          }
          _status = enabled
              ? 'Напоминание включено. Время указано по часовому поясу устройства.'
              : 'Напоминание отключено.';
        } else {
          _status =
              'Разрешение на уведомления не выдано. Разреши уведомления в настройках Android.';
        }
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _status =
              'Не удалось настроить уведомление. Проверь разрешения Android.',
        );
      }
    } finally {
      if (mounted) setState(() => _updatingReminder = false);
    }
  }

  Future<void> _save() async {
    final profile = _profile;
    if (profile == null || _saving) return;
    var saved = false;
    setState(() {
      _saving = true;
      _status = null;
    });
    try {
      await _repository.save(profile);
      if (!mounted) return;
      saved = true;
      setState(() => _status = 'Настройки интересов сохранены');
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = 'Не удалось сохранить настройки');
    } finally {
      if (mounted) setState(() => _saving = false);
    }

    // Applying interests should also populate the feed. Previously saving
    // cleared the old cache but left the news list empty until Refresh was
    // tapped manually.
    final activeProfile = _profile;
    if (saved &&
        mounted &&
        !_loadingNewsCache &&
        activeProfile != null &&
        (activeProfile.topics.isNotEmpty ||
            activeProfile.includeCriticalOutsideInterests)) {
      if (_refreshingNews) {
        // A request for the previous topic selection may still be unwinding.
        // Queue one refresh so saving the new profile cannot leave the feed blank.
        _refreshPendingAfterCurrent = true;
      } else {
        unawaited(_refreshNews());
      }
    }
  }

  Future<void> _refreshNews() async {
    final profile = _profile;
    if (profile == null || _refreshingNews || _loadingNewsCache) return;
    final revisionAtStart = _interestRevision;
    if (profile.topics.isEmpty && !profile.includeCriticalOutsideInterests) {
      setState(() {
        _articles = const [];
        _newsError = null;
        _status =
            'Выберите тему или включите критические новости вне интересов.';
      });
      return;
    }
    setState(() {
      _refreshingNews = true;
      _newsError = null;
    });
    try {
      // Search Russian and English editions, while keeping Russian as the
      // app's output language. Feed locale is not the article's geography.
      final fetchedArticles = await _newsService.fetchInternational(profile);
      if (revisionAtStart != _interestRevision) return;
      if (mounted) {
        setState(() => _lastRssCandidateCount = fetchedArticles.length);
      }
      // Prefer an existing Russian edition when a conservative match is found.
      // Foreign articles without a match remain in the feed unchanged.
      final articles = await _sourceLocalizationService.localizeCandidates(
        fetchedArticles,
      );
      if (revisionAtStart != _interestRevision) return;
      if (mounted) {
        setState(() => _lastLocalizedCandidateCount = articles.length);
      }
      final favorites = await _favoritesRepository.getAll();
      _lessInterested = await _feedbackRepository.loadLessInterested();
      final favoriteProfile = _favoriteAnalytics.analyze(favorites);
      final rankedArticles = _rankByReaction(
        _favoriteAnalytics.rankNews(
          articles,
          favoriteProfile,
          lessInterested: _lessInterested,
        ),
      );
      if (revisionAtStart != _interestRevision) return;
      if (mounted) {
        setState(() => _lastRankedCandidateCount = rankedArticles.length);
      }
      // A digest describes a specific set of articles. Never keep showing a
      // digest generated from the previous feed after a successful refresh.
      await _newsCache.saveDigest(null);
      if (revisionAtStart != _interestRevision) {
        await _newsCache.clear();
        return;
      }
      await _newsCache.saveArticles(
        rankedArticles,
        selectedTopics: profile.topics,
        includeCriticalOutsideInterests:
            profile.includeCriticalOutsideInterests,
      );
      if (revisionAtStart != _interestRevision) {
        // Topic changes clear the cache too, but an in-flight write may finish
        // afterward. Clear again so stale results cannot survive that race.
        await _newsCache.clear();
        return;
      }
      if (!mounted) return;
      setState(() {
        _articles = rankedArticles;
        _hasCompletedNewsFetch = true;
        _showingCachedNews = false;
        _digest = null;
        _digestError = null;
        _newsError = null;
      });
    } catch (error) {
      // A failed request for an old topic selection must not surface an error
      // in the newly selected feed.
      if (!mounted || revisionAtStart != _interestRevision) return;
      final details = error is http.ClientException ? error.message : null;
      setState(() {
        _newsError = details == null || details.isEmpty
            ? 'Не удалось загрузить новости. Проверьте соединение и попробуйте снова.'
            : 'Не удалось загрузить новости: $details';
      });
    } finally {
      if (mounted) {
        setState(() => _refreshingNews = false);
        if (_refreshPendingAfterCurrent) {
          _refreshPendingAfterCurrent = false;
          unawaited(_refreshNews());
        }
      }
    }
  }

  Future<void> _createDigest() async {
    final profile = _profile;
    final engine = widget.aiEngine;
    if (profile == null ||
        engine == null ||
        _generatingDigest ||
        _loadingNewsCache ||
        _refreshingNews) {
      return;
    }
    final revisionAtStart = _interestRevision;
    if ((profile.topics.isEmpty && !profile.includeCriticalOutsideInterests) ||
        _articles.isEmpty) {
      setState(
        () => _digestError = 'Сначала выберите интересы и загрузите новости.',
      );
      return;
    }
    setState(() {
      _generatingDigest = true;
      _digestError = null;
      _digest = null;
    });
    try {
      final digest = await NewsDigestService(
        engine: engine,
      ).createDigest(profile: profile, articles: _articles);
      if (revisionAtStart != _interestRevision) return;
      await _newsCache.saveDigest(digest);
      if (revisionAtStart != _interestRevision) {
        // The selected topics may already have a fresh feed in the cache.
        // A stale digest must not clear those newer articles.
        await _newsCache.saveDigest(null);
        return;
      }
      if (!mounted) return;
      setState(() {
        _digest = digest;
        if (digest == null) {
          _digestError = 'Нет подходящих материалов для дайджеста.';
        }
      });
    } catch (_) {
      // Ignore errors from digest requests started before interests changed.
      if (!mounted || revisionAtStart != _interestRevision) return;
      setState(
        () => _digestError =
            'Не удалось создать дайджест. Проверьте выбранный режим ИИ и попробуйте снова.',
      );
    } finally {
      if (mounted) setState(() => _generatingDigest = false);
    }
  }

  Future<void> _seeLessOf(NewsArticle article) async {
    final topics = article.topics
        .map((topic) => topic.trim().toLowerCase())
        .where((topic) => topic.length >= 2)
        .toSet();
    if (topics.isEmpty) {
      topics.addAll(_favoriteAnalytics.feedbackTermsFor(article).take(3));
    }
    if (topics.isEmpty) return;
    final updated = await _feedbackRepository.addLessInterested(topics);
    final favorites = await _favoritesRepository.getAll();
    final profile = _favoriteAnalytics.analyze(favorites);
    if (!mounted) return;
    setState(() {
      _lessInterested = updated;
      _articles = _favoriteAnalytics.rankNews(
        _articles,
        profile,
        lessInterested: _lessInterested,
      );
      _status = 'Учтено: будем реже поднимать похожие материалы.';
    });
  }

  Future<void> _saveTrailer(NewsArticle article) async {
    await _favoritesRepository.add(
      FavoriteItem(
        id: article.id,
        title: article.title,
        category: FavoriteCategory.trailer,
        addedAt: DateTime.now(),
        description: article.summary,
        interests: article.topics,
        imageUrl: article.thumbnailUrl,
        sourceUrl: (article.videoUrl?.isNotEmpty ?? false)
            ? article.videoUrl
            : article.sourceUrl,
        releaseDate: article.releaseDate,
        releaseDateSourceUrl: article.releaseDateSourceUrl,
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Трейлер «${article.title}» сохранён в избранном'),
      ),
    );
  }

  Future<void> _openArticle(NewsArticle article) async {
    unawaited(_reactToArticle(article, NewsReaction.opened));
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: SystemCorePalette.panel,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  article.sourceName.toUpperCase(),
                  style: const TextStyle(
                    color: SystemCorePalette.green,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  article.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  article.summary.isEmpty
                      ? 'Источник не предоставил краткое описание. Откройте оригинальную публикацию.'
                      : article.summary,
                  style: const TextStyle(color: Colors.white70, height: 1.5),
                ),
                const SizedBox(height: 12),
                Text(
                  'Опубликовано: ${article.publishedAt.toLocal()}',
                  style: const TextStyle(
                    color: SystemCorePalette.muted,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () async {
                    final uri = Uri.tryParse(article.sourceUrl);
                    if (uri != null && uri.scheme == 'https') {
                      await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                    }
                  },
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('ОТКРЫТЬ ИСТОЧНИК'),
                ),
                const SizedBox(height: 8),
                const Text(
                  'В приложении показан RSS-фрагмент и краткое описание. Полный материал принадлежит издателю.',
                  style: TextStyle(
                    color: SystemCorePalette.muted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _addCustomTopic() {
    final topic = _customTopicController.text.trim();
    final profile = _profile;
    if (profile == null || topic.isEmpty) return;
    final normalized = topic.toLowerCase();
    if (profile.topics.any(
      (existing) => existing.trim().toLowerCase() == normalized,
    )) {
      setState(() => _status = 'Эта тема уже добавлена.');
      return;
    }
    if (normalized.length > 60) {
      setState(() => _status = 'Сократи тему до 60 символов.');
      return;
    }
    _customTopicController.clear();
    _toggleTopic(normalized, true);
    setState(
      () => _status = 'Тема добавлена. Сохрани интересы, чтобы применить её.',
    );
  }

  void _toggleTopic(String topic, bool selected) {
    final profile = _profile;
    if (profile == null) return;
    final topics = profile.topics.toSet();
    if (selected) {
      topics.add(topic);
    } else {
      topics.remove(topic);
    }
    _interestRevision++;
    setState(() {
      _profile = profile.copyWith(topics: topics.toList());
      _articles = const [];
      _showingCachedNews = false;
      _hasCompletedNewsFetch = false;
      _digest = null;
      _digestError = null;
    });
    unawaited(_newsCache.clear());
  }

  Future<void> _scrollToInterests() async {
    final target = _interestsSectionKey.currentContext;
    if (target == null) return;
    await Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
      alignment: 0.08,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SystemCorePalette.background,
      body: FutureBuilder<NewsInterestProfile>(
        future: _profileFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(color: SystemCorePalette.green),
            );
          }
          if (snapshot.hasError) {
            return const Center(
              child: Text(
                'Не удалось загрузить интересы. Перезапустите экран.',
              ),
            );
          }
          final profile = _profile ??= snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                children: [
                  const Text(
                    'OMNI_AI',
                    style: TextStyle(
                      color: Color(0xFFE8F5F5),
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const Spacer(),
                  const Icon(
                    Icons.circle,
                    size: 7,
                    color: SystemCorePalette.green,
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'SYSTEM ONLINE',
                    style: TextStyle(
                      color: SystemCorePalette.green,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(
                  16,
                  14,
                  16,
                  14,
                ),
                decoration: BoxDecoration(
                  color: SystemCorePalette.panelElevated,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: SystemCorePalette.border,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: SystemCorePalette.green.withValues(alpha: 0.05),
                      blurRadius: 22,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PERSONAL INTELLIGENCE',
                      style: TextStyle(
                        color: SystemCorePalette.mint,
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.1,
                      ),
                    ),
                    SizedBox(height: 9),
                    Text(
                      'ТВОЯ ЛЕНТА',
                      style: TextStyle(
                        color: Color(0xFFE8F5F5),
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        height: 1.05,
                      ),
                    ),
                    SizedBox(height: 7),
                    Text(
                      'Новости по твоим интересам',
                      style: TextStyle(
                        color: SystemCorePalette.muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'СЕГОДНЯ  /  ПОДОБРАНО ДЛЯ ТЕБЯ',
                style: TextStyle(
                  color: SystemCorePalette.muted,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.9,
                ),
              ),
              const SizedBox(height: 9),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: SystemCorePalette.panel,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: SystemCorePalette.border,
                  ),
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final topic in profile.topics.take(4))
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: SystemCorePalette.green.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(
                            color: SystemCorePalette.green.withValues(
                              alpha: 0.28,
                            ),
                          ),
                        ),
                        child: Text(
                          topic.toUpperCase(),
                          style: const TextStyle(
                            color: SystemCorePalette.green,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    if (profile.topics.length > 4)
                      Text(
                        '+${profile.topics.length - 4} ЕЩЁ',
                        style: const TextStyle(
                          color: SystemCorePalette.muted,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    TextButton(
                      onPressed: _scrollToInterests,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        profile.topics.isEmpty
                            ? '+ ДОБАВИТЬ ИНТЕРЕСЫ'
                            : '+ ИНТЕРЕСЫ',
                        style: const TextStyle(
                          color: SystemCorePalette.mint,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: SystemCorePalette.panel,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: profile.topics.isEmpty
                        ? SystemCorePalette.green
                        : SystemCorePalette.border,
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: ListTile(
                    leading: const Icon(
                      Icons.tune,
                      color: SystemCorePalette.green,
                    ),
                    title: const Text(
                      'Настроить интересы новостей',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      profile.topics.isEmpty
                          ? 'Темы не выбраны — обычная лента будет пустой'
                          : 'Выбрано тем: ${profile.topics.length}',
                      style: const TextStyle(
                        color: SystemCorePalette.muted,
                        fontSize: 12,
                      ),
                    ),
                    trailing: const Icon(
                      Icons.arrow_downward,
                      color: SystemCorePalette.green,
                    ),
                    onTap: () {
                      final target = _interestsSectionKey.currentContext;
                      if (target != null) {
                        Scrollable.ensureVisible(
                          target,
                          duration: const Duration(milliseconds: 350),
                          curve: Curves.easeInOut,
                          alignment: 0.05,
                        );
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: SystemCorePalette.panel,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: SystemCorePalette.border,
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: ListTile(
                    leading: const Icon(
                      Icons.health_and_safety_outlined,
                      color: SystemCorePalette.green,
                    ),
                    title: const Text(
                      'Диагностика системы',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: const Text(
                      'Проверить ленту и сформировать отчёт для поиска ошибок',
                      style: TextStyle(
                        color: SystemCorePalette.muted,
                        fontSize: 12,
                      ),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: SystemCorePalette.green,
                    ),
                    onTap: _runDiagnostics,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: (_refreshingNews || _loadingNewsCache)
                    ? null
                    : _refreshNews,
                icon: _refreshingNews
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label: Text(
                  _refreshingNews ? 'ЗАГРУЗКА…' : 'ОБНОВИТЬ ПЕРСОНАЛЬНУЮ ЛЕНТУ',
                ),
              ),
              if (_newsError != null) ...[
                const SizedBox(height: 12),
                Text(
                  _newsError!,
                  style: const TextStyle(color: Colors.orangeAccent),
                ),
              ],
              if (widget.aiEngine != null) ...[
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed:
                      (_generatingDigest ||
                          _loadingNewsCache ||
                          _refreshingNews)
                      ? null
                      : _createDigest,
                  icon: _generatingDigest
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome),
                  label: Text(
                    _generatingDigest
                        ? 'СОЗДАЮ ДАЙДЖЕСТ…'
                        : 'СОЗДАТЬ AI-ДАЙДЖЕСТ',
                  ),
                ),
                if (_digestError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _digestError!,
                    style: const TextStyle(color: Colors.orangeAccent),
                  ),
                ],
                if (_digest != null) ...[
                  const SizedBox(height: 12),
                  Card(
                    color: SystemCorePalette.panel,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: SelectableText(
                        _digest!,
                        style: const TextStyle(
                          color: Colors.white,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
              if (_loadingNewsCache) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: LinearProgressIndicator(),
                ),
              ],
              if (_showingCachedNews &&
                  !_loadingNewsCache &&
                  _articles.isNotEmpty &&
                  !_refreshingNews) ...[
                const Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: Text(
                    'Показана последняя сохранённая лента; обнови её, чтобы проверить новые публикации.',
                    style: TextStyle(
                      color: SystemCorePalette.muted,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
              if (!_refreshingNews &&
                  _newsError == null &&
                  _articles.isEmpty) ...[
                const SizedBox(height: 12),
                const Icon(
                  Icons.rss_feed,
                  size: 34,
                  color: SystemCorePalette.muted,
                ),
                const SizedBox(height: 8),
                Text(
                  profile.topics.isEmpty &&
                          !profile.includeCriticalOutsideInterests
                      ? 'Лента не загружает новости без выбранных тем. Настройте интересы в разделе ниже или включите критические новости вне интересов.'
                      : (_hasCompletedNewsFetch
                          ? 'По выбранным темам сейчас не найдено подходящих публикаций. Попробуйте добавить более широкую тему или обновить ленту позже.'
                          : 'Нажмите «Обновить», чтобы загрузить свежие материалы по выбранным темам.'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: SystemCorePalette.muted,
                    height: 1.4,
                  ),
                ),
              ],
              if (profile.topics.isEmpty &&
                  !profile.includeCriticalOutsideInterests &&
                  !_loadingNewsCache &&
                  !_refreshingNews &&
                  _newsError == null) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _scrollToInterests,
                  icon: const Icon(Icons.tune),
                  label: const Text('НАСТРОИТЬ ИНТЕРЕСЫ'),
                ),
              ],
              for (final article in _articles) ...[
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(
                    color: SystemCorePalette.panel,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: SystemCorePalette.border),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            width: 3,
                            color: SystemCorePalette.green,
                          ),
                          Expanded(
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => _openArticle(article),
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    14,
                                    13,
                                    12,
                                    12,
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              '${article.sourceName.toUpperCase()}  •  ${article.publishedAt.toLocal().day.toString().padLeft(2, '0')}.${article.publishedAt.toLocal().month.toString().padLeft(2, '0')}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: SystemCorePalette.green,
                                                fontSize: 9,
                                                fontWeight: FontWeight.w600,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                          ),
                                          if (article.contentType == NewsContentType.trailer)
                                            const Icon(
                                              Icons.play_circle_outline,
                                              size: 17,
                                              color: SystemCorePalette.mint,
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        article.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Color(0xFFE8F5F5),
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15,
                                          height: 1.25,
                                        ),
                                      ),
                                      if (article.summary.isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        Text(
                                          article.summary,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: SystemCorePalette.muted,
                                            fontSize: 10,
                                            height: 1.4,
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 10),
                                      Wrap(
                                        spacing: 5,
                                        runSpacing: 6,
                                        crossAxisAlignment: WrapCrossAlignment.center,
                                        children: [
                                          const Padding(
                                            padding: EdgeInsets.only(right: 3),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  'ЧИТАТЬ',
                                                  style: TextStyle(
                                                    color: SystemCorePalette.mint,
                                                    fontSize: 8,
                                                    fontWeight: FontWeight.w700,
                                                    letterSpacing: 0.8,
                                                  ),
                                                ),
                                                SizedBox(width: 4),
                                                Icon(
                                                  Icons.north_east,
                                                  size: 11,
                                                  color: SystemCorePalette.mint,
                                                ),
                                              ],
                                            ),
                                          ),
                                          _ReactionButton(
                                            tooltip: 'Нравится — учитывать в интересах',
                                            icon: Icons.thumb_up_alt_outlined,
                                            color: SystemCorePalette.green,
                                            onPressed: () => _reactToArticle(
                                              article,
                                              NewsReaction.like,
                                            ),
                                          ),
                                          _ReactionButton(
                                            tooltip: 'Не нравится — учитывать в интересах',
                                            icon: Icons.thumb_down_alt_outlined,
                                            color: SystemCorePalette.mint,
                                            onPressed: () => _reactToArticle(
                                              article,
                                              NewsReaction.dislike,
                                            ),
                                          ),
                                          _ReactionButton(
                                            tooltip: 'Показывать меньше похожего',
                                            icon: Icons.remove_circle_outline,
                                            color: SystemCorePalette.muted,
                                            onPressed: () => _seeLessOf(article),
                                          ),
                                          if (article.contentType == NewsContentType.trailer)
                                            _ReactionButton(
                                              tooltip: 'Сохранить трейлер в избранное',
                                              icon: Icons.favorite_border,
                                              color: SystemCorePalette.mint,
                                              onPressed: () => _saveTrailer(article),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 24),
              Text(
                'ВАШИ ИНТЕРЕСЫ',
                key: _interestsSectionKey,
                style: TextStyle(
                  color: SystemCorePalette.green,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Выберите темы. В обычную ленту попадут только материалы по выбранным темам. Если ничего не выбрано, новости не показываются.',
                style: TextStyle(color: Colors.white70, height: 1.4),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _customTopicController,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _addCustomTopic(),
                      maxLength: 60,
                      decoration: const InputDecoration(
                        labelText: 'Своя тема',
                        hintText:
                            'Например: робототехника, экология, Формула-1',
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Добавить тему',
                    onPressed: _addCustomTopic,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                'Можно добавить собственные темы — лента будет искать материалы по ним.',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
              const SizedBox(height: 18),
              if (profile.topics.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final topic in profile.topics)
                      InputChip(
                        label: Text(topic),
                        selected: true,
                        selectedColor: SystemCorePalette.green.withValues(
                          alpha: 0.18,
                        ),
                        onDeleted: () => _toggleTopic(topic, false),
                        deleteIconColor: SystemCorePalette.green,
                      ),
                  ],
                )
              else
                const Text(
                  'Пока нет тем. Добавьте любую тему выше — например, название игры, автора, команду или научное направление.',
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
              const SizedBox(height: 18),
              const Divider(color: Colors.white12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Критические новости вне интересов'),
                subtitle: const Text(
                  'Отдельное исключение. По умолчанию выключено.',
                  style: TextStyle(color: SystemCorePalette.muted),
                ),
                value: profile.includeCriticalOutsideInterests,
                activeThumbColor: SystemCorePalette.green,
                onChanged: (value) {
                  _interestRevision++;
                  setState(() {
                    _profile = profile.copyWith(
                      includeCriticalOutsideInterests: value,
                    );
                    _articles = const [];
                    _showingCachedNews = false;
                    _hasCompletedNewsFetch = false;
                    _digest = null;
                    _digestError = null;
                    _newsError = null;
                  });
                  unawaited(_newsCache.clear());
                },
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(_saving ? 'СОХРАНЕНИЕ…' : 'СОХРАНИТЬ ИНТЕРЕСЫ'),
              ),
              if (_status != null) ...[
                const SizedBox(height: 10),
                Text(
                  _status!,
                  style: const TextStyle(color: SystemCorePalette.green),
                ),
              ],
              const SizedBox(height: 28),
              const Divider(color: Colors.white12),
              const SizedBox(height: 12),
              const Text(
                'РАСПИСАНИЕ ДАЙДЖЕСТА',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Напоминания по местному времени. По нажатию открой приложение, обнови ленту и создай дайджест. Само уведомление не запускает фоновую загрузку или генерацию ИИ.',
                style: TextStyle(color: Colors.white70, height: 1.4),
              ),
              if (_loadingReminderSettings)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: LinearProgressIndicator(),
                )
              else ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Утреннее напоминание — 08:00'),
                  subtitle: const Text('Персональные новости на начало дня'),
                  value: _morningReminder,
                  onChanged: _updatingReminder
                      ? null
                      : (value) => _setReminder(morning: true, enabled: value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Вечернее напоминание — 18:00'),
                  subtitle: const Text('Обновить новости ещё раз за день'),
                  value: _eveningReminder,
                  onChanged: _updatingReminder
                      ? null
                      : (value) => _setReminder(morning: false, enabled: value),
                ),
              ],
              const SizedBox(height: 28),
              const Divider(color: Colors.white12),
              const SizedBox(height: 12),
            ],
          );
        },
      ),
    );
  }
}

class _ReactionButton extends StatelessWidget {
  const _ReactionButton({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: SystemCorePalette.panelElevated,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 36,
            height: 34,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: SystemCorePalette.border),
            ),
            child: Icon(icon, size: 17, color: color),
          ),
        ),
      ),
    );
  }
}
