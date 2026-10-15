import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:omni_ai/features/onboarding/data/user_preferences.dart';

class NewsCenterPage extends StatefulWidget {
  const NewsCenterPage({
    super.key,
    this.repository,
    this.aiEngine,
    this.newsService,
    this.newsCache,
    this.legacyPreferences,
    this.preferencesStore,
  });

  final NewsInterestRepository? repository;
  final AIEngine? aiEngine;
  final NewsRssService? newsService;
  final SharedPreferencesNewsCache? newsCache;
  final UserPreferences? legacyPreferences;
  final UserPreferencesStore? preferencesStore;

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
  late final SharedPreferencesNewsCache _newsCache;
  final NewsFeedbackRepository _newsFeedback = NewsFeedbackRepository();
  Map<String, double> _reactionWeights = const <String, double>{};
  bool _loadingNewsCache = true;
  int _interestRevision = 0;
  List<NewsArticle> _articles = const [];
  bool _showingCachedNews = false;
  bool _refreshingNews = false;
  bool _hasCompletedNewsFetch = false;
  bool _refreshPendingAfterCurrent = false;
  bool _refreshPendingAfterCacheLoad = false;
  int? _lastRssCandidateCount;
  int? _lastLocalizedCandidateCount;
  int? _lastRankedCandidateCount;
  String? _newsError;
  String _newsDiagnosticStage = 'Ещё не запускалась';
  String? _lastNewsFailureStage;
  String? _lastNewsFailureType;
  DateTime? _lastNewsRefreshAt;
  int? _lastRssDurationMs;
  int? _lastLocalizationDurationMs;
  int? _lastRankingDurationMs;
  int? _lastCacheWriteDurationMs;
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
    _newsCache = widget.newsCache ?? SharedPreferencesNewsCache();
    _profileFuture = _loadProfile();
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

  Future<NewsInterestProfile> _loadProfile() async {
    final profile = await _repository.load();
    final legacy = widget.legacyPreferences;
    if (legacy == null || legacy.newsInterestsMigrated) return profile;

    // Preserve the user's previously selected categories when the dedicated
    // news-interest profile is first introduced. Do not restore retired
    // categories such as "life" or Telegram channels as news topics.
    final migratedTopics = profile.topics.isNotEmpty
        ? profile.topics
        : _legacyNewsTopics(legacy.categories);
    var result = profile;
    if (profile.topics.isEmpty && migratedTopics.isNotEmpty) {
      result = profile.copyWith(topics: migratedTopics);
      try {
        await _repository.save(result);
      } catch (_) {
        // Keep the migration retryable if the new profile cannot be saved.
        return profile;
      }
    }

    legacy.newsInterestsMigrated = true;
    final preferencesStore = widget.preferencesStore;
    if (preferencesStore != null) {
      try {
        await preferencesStore.save(legacy);
      } catch (_) {
        // The migrated news profile is already saved; a later launch can
        // safely mark the migration complete without re-importing topics.
      }
    }
    return result;
  }

  List<String> _legacyNewsTopics(List<String> categories) {
    const aliases = <String, String>{
      'anime': 'anime',
      'аниме': 'anime',
      'manga': 'manga',
      'манга': 'manga',
      'games': 'games',
      'gaming': 'games',
      'video games': 'games',
      'игры': 'games',
      'гейминг': 'games',
      'видеоигры': 'games',
      'movies': 'movies',
      'movie': 'movies',
      'films': 'movies',
      'film': 'movies',
      'кино': 'movies',
      'фильмы': 'movies',
      'series': 'series',
      'tv series': 'series',
      'сериалы': 'series',
      'technology': 'technology',
      'tech': 'technology',
      'технологии': 'technology',
      'технология': 'technology',
      'artificial intelligence': 'artificial intelligence',
      'ai': 'artificial intelligence',
      'ии': 'artificial intelligence',
      'нейросети': 'artificial intelligence',
      'искусственный интеллект': 'artificial intelligence',
      'science': 'science',
      'наука': 'science',
      'space': 'space',
      'космос': 'space',
      'gadgets': 'gadgets',
      'гаджеты': 'gadgets',
    };
    final topics = <String>{};
    for (final category in categories) {
      final normalized = category.trim().toLowerCase();
      final topic = aliases[normalized];
      if (topic != null) topics.add(topic);
    }
    return topics.toList()..sort();
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
      final hasFeedInterests =
          profile.topics.isNotEmpty || profile.includeCriticalOutsideInterests;
      final cacheMatchesProfile =
          hasFeedInterests &&
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
      // Saving interests while cache restoration is in flight must not lose
      // the refresh request. Use the current profile, not the older snapshot.
      if (_refreshPendingAfterCacheLoad) {
        _refreshPendingAfterCacheLoad = false;
        unawaited(_refreshNews());
      } else if (hasFeedInterests && _articles.isEmpty) {
        // Do not fetch a generic feed when no interests are selected.
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
          activeProfile != null &&
          (activeProfile.topics.isNotEmpty ||
              activeProfile.includeCriticalOutsideInterests);
      if (_refreshPendingAfterCacheLoad) {
        _refreshPendingAfterCacheLoad = false;
        unawaited(_refreshNews());
      } else if (hasFeedInterests && _articles.isEmpty) {
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

  String _emptyFeedMessage(NewsInterestProfile profile) {
    final hasNoTopics = profile.topics.isEmpty;
    final criticalNewsDisabled = !profile.includeCriticalOutsideInterests;
    if (hasNoTopics && criticalNewsDisabled) {
      return 'Выберите интересы ниже, чтобы наполнить ленту подходящими новостями. Общий поток без персонализации не показывается.';
    }
    if (_hasCompletedNewsFetch) {
      return 'По выбранным темам сейчас не найдено подходящих публикаций. Попробуйте добавить более широкую тему или обновить ленту позже.';
    }
    return 'Нажмите «Обновить», чтобы загрузить свежие материалы по выбранным темам.';
  }

  String _newsDiagnosticNextStep() {
    final profile = _profile;
    if (profile == null) {
      return 'Профиль ещё загружается. Подожди завершения загрузки и повтори диагностику.';
    }
    if (profile.topics.every((topic) => topic.trim().isEmpty) &&
        !profile.includeCriticalOutsideInterests) {
      return 'Добавь хотя бы один интерес и нажми «Сохранить интересы», затем обнови ленту.';
    }
    if (_refreshingNews) {
      return 'Дождись завершения текущего обновления и снова сформируй отчёт.';
    }
    if (_newsError != null) {
      return switch (_lastNewsFailureStage) {
        'Получение RSS-кандидатов' =>
          'Проверь доступ к Google News, DNS/VPN и HTTP-ответ источника; затем повтори обновление.',
        'Поиск русскоязычных дублей и локализация' =>
          'Проверь доступность выбранного AI-провайдера и повтори загрузку; RSS-этап уже завершился.',
        'Персонализация и сортировка' =>
          'Проверь сохранённые реакции, избранное и локальное хранилище; первичная загрузка RSS уже завершилась.',
        'Сохранение кэша' =>
          'Материалы уже загружены; проверь хранилище приложения. Онлайн-лента должна оставаться доступной.',
        _ =>
          'Сохрани отчёт целиком: тип сбоя и этап нужны для следующего точечного теста.',
      };
    }
    if (_lastRssCandidateCount == null) {
      return 'Нажми «Обновить персональную ленту», дождись результата и сформируй отчёт ещё раз.';
    }
    if (_lastRssCandidateCount == 0) {
      return 'Источник не вернул пригодных RSS-статей. Проверь доступность RSS и повтори запрос позже.';
    }
    if ((_lastLocalizedCandidateCount ?? 0) == 0) {
      return 'RSS вернул материалы, но после локализации не осталось кандидатов. Проверь этап локализации.';
    }
    if ((_lastRankedCandidateCount ?? 0) == 0) {
      return 'Материалы получены, но персонализация не оставила результатов. Проверь выбранные темы и фильтр релевантности.';
    }
    if (_articles.isEmpty) {
      return 'Кандидаты были обработаны, но на экране ничего нет. Проверь отображение ленты и состояние кэша.';
    }
    return 'Критических проблем в последнем проходе не обнаружено. Если проблема повторится, скопируй отчёт сразу после неё.';
  }

  Future<void> _runDiagnostics() async {
    final profile = _profile;
    final noFeedInterests =
        profile != null &&
        profile.topics.every((topic) => topic.trim().isEmpty) &&
        !profile.includeCriticalOutsideInterests;
    final report = DiagnosticReport(
      createdAt: DateTime.now(),
      checks: [
        DiagnosticCheck(
          name: 'Профиль интересов',
          status: profile == null
              ? DiagnosticStatus.warning
              : (noFeedInterests
                    ? DiagnosticStatus.warning
                    : DiagnosticStatus.ok),
          details: profile == null
              ? 'Профиль ещё не загружен'
              : noFeedInterests
              ? 'Темы не выбраны; персональная лента намеренно не запускает RSS-запрос'
              : 'Выбрано тем: ${profile.topics.length}',
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
          details: [
            if (_newsError != null) 'Ошибка: $_newsError',
            'Этап: $_newsDiagnosticStage',
            'Последнее обновление: ${_lastNewsRefreshAt?.toLocal().toIso8601String() ?? 'нет данных'}',
            if (_lastNewsFailureStage != null)
              'Этап сбоя: $_lastNewsFailureStage',
            if (_lastNewsFailureType != null) 'Тип сбоя: $_lastNewsFailureType',
            'RSS-кандидатов: ${_lastRssCandidateCount ?? 'нет данных'}',
            'После локализации: ${_lastLocalizedCandidateCount ?? 'нет данных'}',
            'После персонализации: ${_lastRankedCandidateCount ?? 'нет данных'}',
            'На экране: ${_articles.length}',
            'Время RSS: ${_lastRssDurationMs == null ? 'нет данных' : '$_lastRssDurationMs мс'}',
            'Время локализации: ${_lastLocalizationDurationMs == null ? 'нет данных' : '$_lastLocalizationDurationMs мс'}',
            'Время персонализации: ${_lastRankingDurationMs == null ? 'нет данных' : '$_lastRankingDurationMs мс'}',
            'Время записи кэша: ${_lastCacheWriteDurationMs == null ? 'нет данных' : '$_lastCacheWriteDurationMs мс'}',
            if (_refreshingNews) 'Загрузка ещё выполняется',
          ].join('; '),
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
        DiagnosticCheck(
          name: 'Рекомендуемый следующий шаг',
          status: _newsError != null || _articles.isEmpty
              ? DiagnosticStatus.warning
              : DiagnosticStatus.ok,
          details: _newsDiagnosticNextStep(),
        ),
        DiagnosticCheck(
          name: 'Сетевая доступность RSS',
          status: noFeedInterests
              ? DiagnosticStatus.warning
              : (_newsError != null
                    ? DiagnosticStatus.error
                    : (_lastRssCandidateCount == null
                          ? DiagnosticStatus.notChecked
                          : DiagnosticStatus.ok)),
          details: noFeedInterests
              ? 'RSS не запрашивался: не выбраны интересы. Это не доказывает сетевую ошибку; выбери тему, обнови ленту и повтори диагностику.'
              : _newsError != null
              ? 'Последняя операция завершилась с ошибкой на этапе «$_lastNewsFailureStage» ($_lastNewsFailureType): $_newsError'
              : _lastRssCandidateCount == null
              ? 'Нет результата реального RSS-запроса в этой сессии. Нажми «Обновить персональную ленту» и запусти диагностику повторно.'
              : 'Последний RSS-запрос завершился; кандидатов получено: $_lastRssCandidateCount',
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
    final completeReport =
        '$reportText${aiAnalysis == null ? '' : '\n\nАНАЛИЗ ИИ\n$aiAnalysis'}';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: SystemCorePalette.panel,
        title: const Text('Диагностика OMNI AI'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              completeReport,
              style: const TextStyle(color: Colors.white70, height: 1.45),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('ЗАКРЫТЬ'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: completeReport));
              if (mounted && dialogContext.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Диагностический отчёт скопирован'),
                  ),
                );
                Navigator.of(dialogContext).pop();
              }
            },
            icon: const Icon(Icons.copy),
            label: const Text('КОПИРОВАТЬ ОТЧЁТ'),
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
    if (saved && mounted && activeProfile != null) {
      if (_loadingNewsCache) {
        // Cache restoration may hold a stale profile snapshot. Queue refresh
        // until it completes so newly saved interests are not left unapplied.
        _refreshPendingAfterCacheLoad = true;
      } else if (_refreshingNews) {
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
    if (profile.topics.isEmpty && !profile.includeCriticalOutsideInterests) {
      setState(() {
        _articles = const [];
        _digest = null;
        _digestError = null;
        _newsError = null;
        _hasCompletedNewsFetch = false;
        _showingCachedNews = false;
        _newsDiagnosticStage = 'Не запускалась: не выбраны интересы';
        _lastNewsFailureStage = null;
        _lastNewsFailureType = null;
        _lastNewsRefreshAt = DateTime.now();
        _lastRssCandidateCount = null;
        _lastLocalizedCandidateCount = null;
        _lastRankedCandidateCount = null;
        _lastRssDurationMs = null;
        _lastLocalizationDurationMs = null;
        _lastRankingDurationMs = null;
        _lastCacheWriteDurationMs = null;
      });
      await _newsCache.clear();
      return;
    }
    final revisionAtStart = _interestRevision;
    var failureStage = 'Получение RSS-кандидатов';
    setState(() {
      _refreshingNews = true;
      _newsError = null;
      _newsDiagnosticStage = failureStage;
      _lastNewsFailureStage = null;
      _lastNewsFailureType = null;
      _lastNewsRefreshAt = DateTime.now();
      _lastRssCandidateCount = null;
      _lastLocalizedCandidateCount = null;
      _lastRankedCandidateCount = null;
      _lastRssDurationMs = null;
      _lastLocalizationDurationMs = null;
      _lastRankingDurationMs = null;
      _lastCacheWriteDurationMs = null;
    });
    try {
      // Search Russian and English editions, while keeping Russian as the
      // app's output language. Feed locale is not the article's geography.
      final rssWatch = Stopwatch()..start();
      final fetchedArticles = await _newsService.fetchInternational(profile);
      rssWatch.stop();
      _lastRssDurationMs = rssWatch.elapsedMilliseconds;
      if (revisionAtStart != _interestRevision) return;
      if (mounted) {
        setState(() => _lastRssCandidateCount = fetchedArticles.length);
      }
      // Prefer an existing Russian edition when a conservative match is found.
      // Foreign articles without a match remain in the feed unchanged.
      failureStage = 'Поиск русскоязычных дублей и локализация';
      if (mounted) setState(() => _newsDiagnosticStage = failureStage);
      final localizationWatch = Stopwatch()..start();
      final articles = await _sourceLocalizationService.localizeCandidates(
        fetchedArticles,
      );
      localizationWatch.stop();
      _lastLocalizationDurationMs = localizationWatch.elapsedMilliseconds;
      if (revisionAtStart != _interestRevision) return;
      if (mounted) {
        setState(() => _lastLocalizedCandidateCount = articles.length);
      }
      failureStage = 'Персонализация и сортировка';
      if (mounted) setState(() => _newsDiagnosticStage = failureStage);
      final rankingWatch = Stopwatch()..start();
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
      rankingWatch.stop();
      _lastRankingDurationMs = rankingWatch.elapsedMilliseconds;
      if (revisionAtStart != _interestRevision) return;
      if (mounted) {
        setState(() => _lastRankedCandidateCount = rankedArticles.length);
      }
      // The network feed is usable independently of local cache persistence.
      // Publish the fresh articles first so a storage failure cannot turn a
      // successful RSS refresh into an empty screen.
      if (!mounted) return;
      setState(() {
        _articles = rankedArticles;
        _hasCompletedNewsFetch = true;
        _showingCachedNews = false;
        _digest = null;
        _digestError = null;
        _newsError = null;
      });

      // A digest describes a specific set of articles. Never keep showing a
      // digest generated from the previous feed after a successful refresh.
      // Cache writes are best-effort: report a storage warning, but keep the
      // freshly fetched articles visible if persistence fails.
      try {
        failureStage = 'Сохранение кэша';
        if (mounted) setState(() => _newsDiagnosticStage = failureStage);
        final cacheWatch = Stopwatch()..start();
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
        cacheWatch.stop();
        _lastCacheWriteDurationMs = cacheWatch.elapsedMilliseconds;
        if (revisionAtStart != _interestRevision) {
          // Topic changes clear the cache too, but an in-flight write may finish
          // afterward. Clear again so stale results cannot survive that race.
          await _newsCache.clear();
          return;
        }
      } catch (error) {
        cacheWatch.stop();
        _lastCacheWriteDurationMs = cacheWatch.elapsedMilliseconds;
        if (mounted && revisionAtStart == _interestRevision) {
          setState(() {
            _lastNewsFailureStage = 'Сохранение кэша';
            _lastNewsFailureType = error.runtimeType.toString();
            _newsDiagnosticStage = 'Ошибка сохранения кэша';
            _newsError =
                'Новости загружены, но не удалось сохранить их для офлайн-доступа.';
          });
        }
      }
    } catch (error) {
      // A failed request for an old topic selection must not surface an error
      // in the newly selected feed.
      if (!mounted || revisionAtStart != _interestRevision) return;
      final details = error is http.ClientException ? error.message : null;
      setState(() {
        _lastNewsFailureStage = failureStage;
        _lastNewsFailureType = error.runtimeType.toString();
        _newsDiagnosticStage = 'Ошибка: $failureStage';
        _newsError = details == null || details.isEmpty
            ? 'Не удалось загрузить новости. Проверьте соединение и попробуйте снова.'
            : 'Не удалось загрузить новости: $details';
      });
    } finally {
      if (mounted) {
        setState(() {
          _refreshingNews = false;
          if (_lastNewsFailureStage == null) {
            _newsDiagnosticStage = 'Завершена';
          }
        });
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
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                decoration: BoxDecoration(
                  color: SystemCorePalette.panelElevated,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: SystemCorePalette.border),
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
                  border: Border.all(color: SystemCorePalette.border),
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
                          color: SystemCorePalette.green.withValues(
                            alpha: 0.08,
                          ),
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
                  _emptyFeedMessage(profile),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: SystemCorePalette.muted,
                    height: 1.4,
                  ),
                ),
              ],
              if (profile.topics.isEmpty &&
                  !profile.includeCriticalOutsideInterests) ...[
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
                          Container(width: 3, color: SystemCorePalette.green),
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                          if (article.contentType ==
                                              NewsContentType.trailer)
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
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          const Padding(
                                            padding: EdgeInsets.only(right: 3),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  'ЧИТАТЬ',
                                                  style: TextStyle(
                                                    color:
                                                        SystemCorePalette.mint,
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
                                            tooltip:
                                                'Нравится — учитывать в интересах',
                                            icon: Icons.thumb_up_alt_outlined,
                                            color: SystemCorePalette.green,
                                            onPressed: () => _reactToArticle(
                                              article,
                                              NewsReaction.like,
                                            ),
                                          ),
                                          _ReactionButton(
                                            tooltip:
                                                'Не нравится — учитывать в интересах',
                                            icon: Icons.thumb_down_alt_outlined,
                                            color: SystemCorePalette.mint,
                                            onPressed: () => _reactToArticle(
                                              article,
                                              NewsReaction.dislike,
                                            ),
                                          ),
                                          _ReactionButton(
                                            tooltip:
                                                'Показывать меньше похожего',
                                            icon: Icons.remove_circle_outline,
                                            color: SystemCorePalette.muted,
                                            onPressed: () =>
                                                _seeLessOf(article),
                                          ),
                                          if (article.contentType ==
                                              NewsContentType.trailer)
                                            _ReactionButton(
                                              tooltip:
                                                  'Сохранить трейлер в избранное',
                                              icon: Icons.favorite_border,
                                              color: SystemCorePalette.mint,
                                              onPressed: () =>
                                                  _saveTrailer(article),
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
                          ? 'Выберите темы, чтобы включить ленту'
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
                  border: Border.all(color: SystemCorePalette.border),
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
                'Лента показывает новости только по выбранным интересам. Добавьте темы ниже, чтобы начать.',
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
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:omni_ai/features/news/models/news_article.dart';
import 'package:omni_ai/features/news/models/news_interest_profile.dart';
import 'package:omni_ai/features/news/services/news_relevance_filter.dart';

/// The failure class identifies the stage that prevented an RSS request from
/// producing usable data, without retaining response bodies or credentials.
enum NewsRssFailureKind {
  timeout,
  network,
  httpStatus,
  emptyResponse,
  malformedRss,
}

class NewsRssException extends http.ClientException {
  NewsRssException({
    required this.kind,
    required String message,
    this.statusCode,
    Uri? uri,
  }) : super(message, uri);

  final NewsRssFailureKind kind;
  final int? statusCode;
}

/// Reads public Google News RSS search results. No API key is embedded in the
/// application. RSS excerpts are displayed with source attribution; full
/// publisher articles remain at their original source.
class NewsRssService {
  NewsRssService({http.Client? client, NewsRelevanceFilter? filter})
    : _client = client ?? http.Client(),
      _filter = filter ?? const NewsRelevanceFilter();

  final http.Client _client;
  final NewsRelevanceFilter _filter;

  static const _topicKeywords = <String, List<String>>{
    'games': ['game', 'gaming', 'video game', 'игр', 'гейминг'],
    'anime': ['anime', 'аниме'],
    'manga': ['manga', 'манга'],
    'movies': ['movie', 'movies', 'cinema', 'film', 'кино', 'фильм'],
    'series': ['series', 'tv series', 'streaming', 'сериал', 'сериалы'],
    'technology': ['technology', 'tech', 'технолог', 'техника'],
    'artificial intelligence': [
      'artificial intelligence',
      ' ai ',
      'ии',
      'искусственн',
      'нейросет',
    ],
    'science': ['science', 'scientific', 'наук', 'исследован'],
    'space': [
      'space',
      'astronomy',
      'spaceflight',
      'космос',
      'астроном',
      'космич',
    ],
    'gadgets': [
      'gadget',
      'electronics',
      'smartphone',
      'гаджет',
      'смартфон',
      'электроник',
    ],
  };

  // Only high-impact public-safety events bypass topic preferences, and only
  // when the user explicitly enables critical news in their profile.
  static const _criticalNewsKeywords = <String>[
    'state of emergency',
    'emergency declared',
    'major earthquake',
    'earthquake of magnitude',
    'tsunami warning',
    'evacuation order',
    'mass casualty',
    'critical infrastructure outage',
    'national emergency',
    'terrorist attack',
    'major wildfire',
    'severe flooding',
    'чрезвычайное положение',
    'режим чс',
    'объявлена эвакуация',
    'угроза цунами',
    'землетрясение магнитудой',
    'крупное землетрясение',
    'массовая гибель',
    'теракт',
    'крупный пожар',
    'масштабное наводнение',
    'авария на атомной станции',
    'радиационная авария',
  ];

  bool _isCriticalNews(String text) {
    final normalized = ' ${text.toLowerCase()} ';
    return _criticalNewsKeywords.any(
      (keyword) => _containsKeyword(normalized, keyword),
    );
  }

  static const _topicQueries = <String, String>{
    'games': 'video games gaming',
    'anime': 'anime',
    'manga': 'manga',
    'movies': 'movies cinema',
    'series': 'TV series streaming',
    'technology': 'technology',
    'artificial intelligence': 'artificial intelligence AI',
    'science': 'science',
    'space': 'space exploration astronomy',
    'gadgets': 'gadgets consumer electronics',
  };

  /// Collects candidates from Russian and English Google News editions.
  /// Edition locale describes the feed, not the article's actual geography.
  Future<List<NewsArticle>> fetchInternational(
    NewsInterestProfile profile,
  ) async {
    if (profile.topics.every((topic) => topic.trim().isEmpty) &&
        !profile.includeCriticalOutsideInterests) {
      return const <NewsArticle>[];
    }
    const locales = <List<String>>[
      ['ru', 'RU'],
      ['en', 'US'],
      ['en', 'GB'],
    ];
    var successfulEditions = 0;
    final failedEditions = <String>[];
    final batches = await Future.wait(
      locales.map((locale) async {
        try {
          final articles = await fetch(
            profile.copyWith(
              languages: <String>[locale[0]],
              regions: <String>[locale[1]],
            ),
            applyRelevanceFilter: false,
          );
          successfulEditions++;
          return articles;
        } catch (error) {
          // One unavailable edition should not block the remaining sources.
          // Keep only locale and error type so diagnostics remain useful
          // without exposing response bodies or arbitrary network payloads.
          failedEditions.add(
            '${locale[0]}-${locale[1]}: ${_failureSummary(error)}',
          );
          return const <NewsArticle>[];
        }
      }),
    );
    if (successfulEditions == 0) {
      throw http.ClientException(
        'All international news editions are unavailable '
        '(${failedEditions.join(', ')}).',
      );
    }
    // A nominally successful HTTP response can still contain no usable RSS
    // items. Never turn an all-empty result into a silent blank feed: report
    // whether the likely cause is a partial outage or empty source responses.
    if (batches.every((batch) => batch.isEmpty)) {
      if (failedEditions.isNotEmpty) {
        throw http.ClientException(
          'No articles were returned and some international news editions '
          'failed (${failedEditions.join(', ')}).',
        );
      }
      throw http.ClientException(
        'International news sources returned no usable articles.',
      );
    }

    final byUrl = <String, NewsArticle>{};
    for (final article in batches.expand((batch) => batch)) {
      // Apply the same tracking-parameter normalization across editions as
      // within a single feed, while retaining the original user-facing URL.
      final url = _canonicalUrl(article.sourceUrl);
      if (url.isEmpty) continue;
      final previous = byUrl[url];
      if (previous == null || _preferArticle(article, previous)) {
        byUrl[url] = article;
      }
    }

    // Different editions can repeat a headline with tracking URLs.
    final byTitle = <String, NewsArticle>{};
    for (final article in byUrl.values) {
      final titleKey = _normalizedTitle(article.title);
      if (titleKey.isEmpty) continue;
      final previous = byTitle[titleKey];
      if (previous == null || _preferArticle(article, previous)) {
        byTitle[titleKey] = article;
      }
    }

    final unrestrictedProfile = profile.copyWith(
      topics: profile.topics
          .map(_canonicalTopic)
          .toSet()
          .toList(growable: false),
      languages: const <String>[],
      regions: const <String>[],
    );
    if (unrestrictedProfile.topics.isEmpty &&
        !unrestrictedProfile.includeCriticalOutsideInterests) {
      return List<NewsArticle>.unmodifiable(
        byTitle.values.toList()
          ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt)),
      );
    }
    return _filter.filter(byTitle.values, unrestrictedProfile);
  }

  Future<List<NewsArticle>> fetch(
    NewsInterestProfile profile, {
    bool applyRelevanceFilter = true,
  }) async {
    if (profile.topics.every((topic) => topic.trim().isEmpty) &&
        !profile.includeCriticalOutsideInterests) {
      return const <NewsArticle>[];
    }
    final isDiscoveryFeed =
        profile.topics.isEmpty && !profile.includeCriticalOutsideInterests;
    final language = profile.languages
        .map((value) => value.trim().toLowerCase())
        .firstWhere((value) => value.isNotEmpty, orElse: () => 'ru');
    final region = profile.regions
        .map((value) => value.trim().toUpperCase())
        .firstWhere((value) => value.isNotEmpty, orElse: () => 'RU');
    final canonicalTopics = profile.topics
        .map(_canonicalTopic)
        .where((topic) => topic.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final topicQuery = canonicalTopics
        .map((topic) => _topicQueries[topic] ?? topic)
        .join(' OR ');
    final criticalQuery = profile.includeCriticalOutsideInterests
        ? _criticalNewsKeywords.map((keyword) => '"$keyword"').join(' OR ')
        : '';
    final query = isDiscoveryFeed
        ? 'news'
        : topicQuery.isEmpty
        ? criticalQuery
        : criticalQuery.isEmpty
        ? topicQuery
        : '($topicQuery) OR ($criticalQuery)';
    final canonicalProfile = profile.copyWith(topics: canonicalTopics);
    if (query.isEmpty && !isDiscoveryFeed) {
      return const <NewsArticle>[];
    }
    // With no selected interests, use the edition's top-stories feed rather
    // than searching for the literal word "news". The latter biases discovery
    // toward headlines that happen to contain that word and can hide ordinary
    // current-affairs headlines from the user's feed.
    final uri =
        Uri.https('news.google.com', isDiscoveryFeed ? '/rss' : '/rss/search', {
          if (!isDiscoveryFeed) 'q': query,
          'hl': language == 'ru' ? 'ru' : language,
          'gl': region,
          'ceid': '$region:$language',
        });
    late final http.Response response;
    try {
      response = await _client
          .get(uri, headers: const {'User-Agent': 'OMNI-AI-News/1.0'})
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw NewsRssException(
        kind: NewsRssFailureKind.timeout,
        message: 'News source request timed out after 20 seconds.',
        uri: uri,
      );
    } on SocketException {
      throw NewsRssException(
        kind: NewsRssFailureKind.network,
        message: 'News source network connection failed.',
        uri: uri,
      );
    } on http.ClientException catch (error) {
      throw NewsRssException(
        kind: NewsRssFailureKind.network,
        message: 'News source request failed: ${error.runtimeType}.',
        uri: uri,
      );
    }
    if (response.statusCode != 200) {
      throw NewsRssException(
        kind: NewsRssFailureKind.httpStatus,
        statusCode: response.statusCode,
        message: 'News source returned HTTP ${response.statusCode}.',
        uri: uri,
      );
    }

    final xml = utf8.decode(response.bodyBytes, allowMalformed: true).trim();
    if (xml.isEmpty) {
      throw NewsRssException(
        kind: NewsRssFailureKind.emptyResponse,
        message: 'News source returned an empty response body.',
        uri: uri,
      );
    }
    if (!RegExp(r'<(?:rss|feed)\b', caseSensitive: false).hasMatch(xml)) {
      throw NewsRssException(
        kind: NewsRssFailureKind.malformedRss,
        message: 'News source response is not recognizable RSS or Atom XML.',
        uri: uri,
      );
    }
    final articles = _parseItems(
      xml,
      language,
      region.toLowerCase(),
      selectedTopics: canonicalTopics,
    );
    final unique = <String, NewsArticle>{};
    for (final article in articles) {
      final key = _canonicalUrl(article.sourceUrl);
      if (key.isEmpty) continue;
      final previous = unique[key];
      if (previous == null || _preferArticle(article, previous)) {
        unique[key] = article;
      }
    }
    if (!applyRelevanceFilter) {
      final candidates = unique.values.toList(growable: false)
        ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
      return List<NewsArticle>.unmodifiable(candidates);
    }
    if (isDiscoveryFeed) {
      return List<NewsArticle>.unmodifiable(
        unique.values.toList()
          ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt)),
      );
    }
    return _filter.filter(unique.values, canonicalProfile);
  }

  /// Removes common tracking parameters without changing the URL shown to
  /// the user. This lets editions deduplicate the same story when publishers
  /// append campaign IDs or fragments to an otherwise identical link.
  String _canonicalUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return '';
    const trackingKeys = <String>{
      'fbclid',
      'gclid',
      'dclid',
      'mc_cid',
      'mc_eid',
      'ref',
      'ref_src',
      'source',
    };
    final kept =
        uri.queryParametersAll.entries.where((entry) {
          final key = entry.key.toLowerCase();
          return !key.startsWith('utm_') && !trackingKeys.contains(key);
        }).toList()..sort((a, b) {
          final byKey = a.key.toLowerCase().compareTo(b.key.toLowerCase());
          return byKey != 0
              ? byKey
              : a.value.join(',').compareTo(b.value.join(','));
        });
    final query = <String, dynamic>{
      for (final entry in kept) entry.key: entry.value,
    };
    return uri
        .replace(
          fragment: '',
          query: query.isEmpty ? '' : null,
          queryParameters: query.isEmpty ? null : query,
          path: uri.path.isEmpty ? '/' : uri.path,
        )
        .toString();
  }

  String _canonicalTopic(String topic) {
    final normalized = topic.trim().toLowerCase();
    return switch (normalized) {
      'ai' || 'ии' || 'нейросети' => 'artificial intelligence',
      'tech' || 'technology news' => 'technology',
      'gaming' || 'video games' => 'games',
      'cinema' || 'film' || 'films' => 'movies',
      'tv' || 'tv series' => 'series',
      _ => normalized,
    };
  }

  String _normalizedTitle(String title) => title
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'''[.,!?;:()\[\]{}"'«»—–-]'''), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  bool _preferArticle(NewsArticle candidate, NewsArticle current) {
    if (candidate.publishedAt.isAfter(current.publishedAt)) return true;
    if (candidate.publishedAt.isBefore(current.publishedAt)) return false;
    if (candidate.summary.trim().length != current.summary.trim().length) {
      return candidate.summary.trim().length > current.summary.trim().length;
    }
    return candidate.isVerified && !current.isVerified;
  }

  List<NewsArticle> _parseItems(
    String xml,
    String language,
    String? profileRegion, {
    List<String> selectedTopics = const <String>[],
  }) {
    final items = RegExp(
      r'<item(?:\s[^>]*)?>([\s\S]*?)</item>',
      caseSensitive: false,
    ).allMatches(xml);
    // Only use the query-based fallback when none of the returned items
    // can be matched to the selected interests. Otherwise an unrelated item
    // in a mixed RSS response could inherit the selected topics.
    final hasSelectedTopicMatch = items.any((match) {
      final item = match.group(1) ?? '';
      final title = _tag(item, 'title');
      final link = _tag(item, 'link');
      final published =
          _parseDate(_tag(item, 'pubDate')) ??
          _parseDate(_tag(item, 'dc:date'));
      final uri = Uri.tryParse(link);
      // Invalid RSS items must not suppress query-based topic fallback for
      // otherwise valid results later in the same response.
      if (title.isEmpty ||
          link.isEmpty ||
          published == null ||
          uri == null ||
          uri.scheme != 'https' ||
          uri.host.isEmpty) {
        return false;
      }
      final description = _stripMarkup(
        _tag(item, 'description', decodeEntities: false),
      );
      final normalized =
          ' ${title.toLowerCase()} ${description.toLowerCase()} ';
      return selectedTopics.any((topic) {
        final keywords = _topicKeywords[topic];
        if (keywords != null) {
          return keywords.any(
            (keyword) => _containsKeyword(normalized, keyword),
          );
        }
        return _containsKeyword(normalized, topic);
      });
    });
    final result = <NewsArticle>[];
    for (final match in items) {
      final item = match.group(1) ?? '';
      final title = _tag(item, 'title');
      final link = _tag(item, 'link');
      final description = _tag(item, 'description', decodeEntities: false);
      final published =
          _parseDate(_tag(item, 'pubDate')) ??
          _parseDate(_tag(item, 'dc:date'));
      if (title.isEmpty || link.isEmpty || published == null) continue;
      final uri = Uri.tryParse(link);
      if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) continue;
      final sourceName = _tag(item, 'source').isNotEmpty
          ? _tag(item, 'source')
          : uri.host;
      final text = _stripMarkup(description);
      final normalized = ' ${title.toLowerCase()} ${text.toLowerCase()} ';
      final detectedTopics = _topicKeywords.entries
          .where(
            (entry) => entry.value.any(
              (keyword) => _containsKeyword(normalized, keyword),
            ),
          )
          .map((entry) => entry.key)
          .toSet();
      // User-defined interests must remain usable even when they are not one
      // of the built-in topic categories. Otherwise RSS can return relevant
      // results that the strict relevance filter silently drops.
      for (final topic in selectedTopics) {
        if (!_topicKeywords.containsKey(topic) &&
            _containsKeyword(normalized, topic)) {
          detectedTopics.add(topic);
        }
      }
      final isCritical = _isCriticalNews('$title $text');
      // Google News already searched the selected topic query. If the
      // entire response lacks detectable selected-topic keywords, preserve
      // the query-matched results. Do not apply this fallback item by item:
      // that would also admit unrelated items from a mixed response.
      if (!hasSelectedTopicMatch && !isCritical) {
        detectedTopics.addAll(selectedTopics);
      }
      final topics = detectedTopics.toList(growable: false);
      result.add(
        NewsArticle(
          id: uri.toString(),
          title: title,
          summary: text,
          sourceName: sourceName,
          sourceUrl: uri.toString(),
          publishedAt: published.toUtc(),
          topics: topics,
          language: language,
          isCritical: isCritical,
          region: profileRegion,
          isVerified: true,
        ),
      );
    }
    return result;
  }

  bool _containsKeyword(String text, String keyword) {
    final normalizedKeyword = keyword.toLowerCase();
    // Short Cyrillic abbreviations such as «ИИ» must match as whole words;
    // substring matching would incorrectly classify «России» as AI news.
    if (normalizedKeyword == 'ии') {
      return RegExp(
        r'''(^|[\s.,!?()\[\]{}:;"'«»—-])ии([\s.,!?()\[\]{}:;"'«»—-]|$)''',
        caseSensitive: false,
      ).hasMatch(text);
    }
    return text.contains(normalizedKeyword);
  }

  DateTime? _parseDate(String value) {
    final input = value.trim();
    if (input.isEmpty) return null;
    try {
      return HttpDate.parse(input).toUtc();
    } on HttpException {
      // RSS feeds may contain arbitrary date strings. Treat malformed dates as
      // missing publication metadata so the item is skipped safely.
      return DateTime.tryParse(input)?.toUtc();
    } on FormatException {
      return DateTime.tryParse(input)?.toUtc();
    }
  }

  String _tag(String xml, String name, {bool decodeEntities = true}) {
    final escapedName = RegExp.escape(name);
    final match = RegExp(
      '<$escapedName(?:\\s[^>]*)?>([\\s\\S]*?)</$escapedName>',
      caseSensitive: false,
    ).firstMatch(xml);
    if (match == null) return '';
    var value = match.group(1) ?? '';
    value = value.replaceAllMapped(
      RegExp(r'<!\[CDATA\[([\s\S]*?)\]\]>'),
      (match) => match.group(1) ?? '',
    );
    return (decodeEntities ? _decodeEntities(value) : value).trim();
  }

  String _stripMarkup(String value) {
    final decoded = _decodeEntities(
      value.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' '),
    );
    // Encoded angle brackets are text, not markup. Remove the brackets while
    // retaining their contents so excerpts remain readable and predictable.
    return decoded.replaceAll('<', '').replaceAll('>', '').trim();
  }

  String _decodeEntities(String value) {
    final namedDecoded = value
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&#8217;', '’')
        .replaceAll('&#8211;', '–')
        .replaceAll('&#160;', ' ');

    // RSS publishers commonly encode punctuation and symbols as decimal or
    // hexadecimal numeric references. Decode valid Unicode scalar values only.
    return namedDecoded.replaceAllMapped(
      RegExp(r'&#(x[0-9a-f]+|[0-9]+);', caseSensitive: false),
      (match) {
        final token = match.group(1)!;
        final codePoint = token.toLowerCase().startsWith('x')
            ? int.tryParse(token.substring(1), radix: 16)
            : int.tryParse(token);
        if (codePoint == null ||
            codePoint <= 0 ||
            codePoint > 0x10ffff ||
            (codePoint >= 0xd800 && codePoint <= 0xdfff)) {
          return match.group(0)!;
        }
        return String.fromCharCode(codePoint);
      },
    );
  }

  static String _failureSummary(Object error) {
    if (error is NewsRssException) {
      final code = error.statusCode == null ? '' : ' HTTP ${error.statusCode}';
      return 'ClientException/${error.kind.name}$code';
    }
    if (error is TimeoutException) return 'TimeoutException/timeout';
    if (error is SocketException) return 'SocketException/network';
    return error.runtimeType.toString();
  }

  void dispose() => _client.close();
}
