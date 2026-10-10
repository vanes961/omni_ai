import 'dart:async';

import 'package:flutter/material.dart';
import 'package:omni_ai/core/ai_engine/services/ai_engine.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:omni_ai/features/news/data/news_interest_repository.dart';
import 'package:omni_ai/features/news/data/shared_preferences_news_cache.dart';
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
  const NewsCenterPage({super.key, this.repository, this.aiEngine});

  final NewsInterestRepository? repository;
  final AIEngine? aiEngine;

  @override
  State<NewsCenterPage> createState() => _NewsCenterPageState();
}

class _NewsCenterPageState extends State<NewsCenterPage> {
  static const _topicOptions = <String, String>{
    'games': 'Игры',
    'anime': 'Аниме',
    'manga': 'Манга',
    'movies': 'Кино',
    'series': 'Сериалы',
    'technology': 'Технологии',
    'artificial intelligence': 'Искусственный интеллект',
    'science': 'Наука',
    'space': 'Космос',
    'gadgets': 'Гаджеты',
  };

  late final NewsInterestRepository _repository;
  late final bool _ownsRepository;
  late Future<NewsInterestProfile> _profileFuture;
  NewsInterestProfile? _profile;
  bool _saving = false;
  String? _status;
  final NewsRssService _newsService = NewsRssService();
  final FavoritesRepository _favoritesRepository = FavoritesRepository();
  final InterestFeedbackRepository _feedbackRepository = InterestFeedbackRepository();
  Set<String> _lessInterested = <String>{};
  final FavoriteInterestAnalytics _favoriteAnalytics =
      const FavoriteInterestAnalytics();
  final NewsSourceLocalizationService _sourceLocalizationService =
      const NewsSourceLocalizationService();
  final SharedPreferencesNewsCache _newsCache = SharedPreferencesNewsCache();
  bool _loadingNewsCache = true;
  int _interestRevision = 0;
  List<NewsArticle> _articles = const [];
  bool _showingCachedNews = false;
  bool _refreshingNews = false;
  String? _newsError;
  bool _generatingDigest = false;
  String? _digest;
  String? _digestError;
  final NewsReminderService _reminderService = NewsReminderService();
  bool _morningReminder = false;
  bool _eveningReminder = false;
  bool _loadingReminderSettings = true;
  bool _updatingReminder = false;

  @override
  void initState() {
    super.initState();
    _ownsRepository = widget.repository == null;
    _repository =
        widget.repository ?? SharedPreferencesNewsInterestRepository();
    _profileFuture = _repository.load();
    unawaited(_loadReminderSettings());
    unawaited(_loadNewsCache());
  }

  @override
  void dispose() {
    if (_ownsRepository) unawaited(_repository.dispose());
    _newsService.dispose();
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
      ]);
      final savedTopics = cached[2] as List<String>?;
      final favorites = await _favoritesRepository.getAll();
      _lessInterested = await _feedbackRepository.loadLessInterested();
      final favoriteProfile = _favoriteAnalytics.analyze(favorites);
      final cachedArticles = _favoriteAnalytics.rankNews(
        (cached[0] as List<NewsArticle>),
        favoriteProfile,
        lessInterested: _lessInterested,
      );
      final selectedTopics = _normalizeTopics(profile.topics);
      final cacheMatchesProfile = savedTopics != null &&
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
      if ((loadedProfile ?? _profile)?.topics.isNotEmpty == true &&
          _articles.isEmpty) {
        unawaited(_refreshNews());
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingNewsCache = false);
      // Cache restoration is best-effort. If storage is unavailable or the
      // cached payload cannot be read, still attempt a fresh feed rather than
      // leaving users with a blank screen until they manually tap Refresh.
      if ((loadedProfile ?? _profile)?.topics.isNotEmpty == true &&
          _articles.isEmpty) {
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

  Future<void> _setReminder({required bool morning, required bool enabled}) async {
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
          _status = 'Разрешение на уведомления не выдано. Разреши уведомления в настройках Android.';
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() => _status = 'Не удалось настроить уведомление. Проверь разрешения Android.');
      }
    } finally {
      if (mounted) setState(() => _updatingReminder = false);
    }
  }

  Future<void> _save() async {
    final profile = _profile;
    if (profile == null || _saving) return;
    setState(() {
      _saving = true;
      _status = null;
    });
    try {
      await _repository.save(profile);
      if (!mounted) return;
      setState(() => _status = 'Настройки интересов сохранены');
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = 'Не удалось сохранить настройки');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _refreshNews() async {
    final profile = _profile;
    if (profile == null || _refreshingNews || _loadingNewsCache) return;
    final revisionAtStart = _interestRevision;
    if (profile.topics.isEmpty) {
      setState(() {
        _articles = const [];
        _newsError = null;
        _status = 'Выберите хотя бы одну тему, чтобы получить персональные новости.';
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
      // Prefer an existing Russian edition when a conservative match is found.
      // Foreign articles without a match remain in the feed unchanged.
      final articles = await _sourceLocalizationService.localizeCandidates(
        fetchedArticles,
      );
      final favorites = await _favoritesRepository.getAll();
      _lessInterested = await _feedbackRepository.loadLessInterested();
      final favoriteProfile = _favoriteAnalytics.analyze(favorites);
      final rankedArticles = _favoriteAnalytics.rankNews(
        articles,
        favoriteProfile,
        lessInterested: _lessInterested,
      );
      if (revisionAtStart != _interestRevision) return;
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
        _showingCachedNews = false;
        _digest = null;
        _digestError = null;
        _newsError = null;
      });
    } catch (_) {
      // A failed request for an old topic selection must not surface an error
      // in the newly selected feed.
      if (!mounted || revisionAtStart != _interestRevision) return;
      setState(() {
        _newsError = 'Не удалось загрузить новости. Проверьте соединение и попробуйте снова.';
      });
    } finally {
      if (mounted) setState(() => _refreshingNews = false);
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
    if (profile.topics.isEmpty || _articles.isEmpty) {
      setState(() => _digestError = 'Сначала выберите интересы и загрузите новости.');
      return;
    }
    setState(() {
      _generatingDigest = true;
      _digestError = null;
      _digest = null;
    });
    try {
      final digest = await NewsDigestService(engine: engine).createDigest(
        profile: profile,
        articles: _articles,
      );
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
      setState(() => _digestError = 'Не удалось создать дайджест. Проверьте выбранный режим ИИ и попробуйте снова.');
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
      SnackBar(content: Text('Трейлер «${article.title}» сохранён в избранном')),
    );
  }

  Future<void> _openArticle(NewsArticle article) async {
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
                Text(article.sourceName.toUpperCase(),
                    style: const TextStyle(color: SystemCorePalette.green, fontSize: 12)),
                const SizedBox(height: 8),
                Text(article.title,
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Text(article.summary.isEmpty
                    ? 'Источник не предоставил краткое описание. Откройте оригинальную публикацию.'
                    : article.summary,
                    style: const TextStyle(color: Colors.white70, height: 1.5)),
                const SizedBox(height: 12),
                Text('Опубликовано: ${article.publishedAt.toLocal()}',
                    style: const TextStyle(color: SystemCorePalette.muted, fontSize: 12)),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () async {
                    final uri = Uri.tryParse(article.sourceUrl);
                    if (uri != null && uri.scheme == 'https') {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  },
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('ОТКРЫТЬ ИСТОЧНИК'),
                ),
                const SizedBox(height: 8),
                const Text('В приложении показан RSS-фрагмент и краткое описание. Полный материал принадлежит издателю.',
                    style: TextStyle(color: SystemCorePalette.muted, fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
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
      _digest = null;
      _digestError = null;
    });
    unawaited(_newsCache.clear());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SystemCorePalette.background,
      appBar: AppBar(
        title: const Text('НОВОСТНОЙ ЦЕНТР'),
        backgroundColor: SystemCorePalette.panel,
        foregroundColor: Colors.white,
      ),
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
              const Text(
                'ВАШИ ИНТЕРЕСЫ',
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
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final entry in _topicOptions.entries)
                    FilterChip(
                      label: Text(entry.value),
                      selected: profile.topics.contains(entry.key),
                      onSelected: (selected) =>
                          _toggleTopic(entry.key, selected),
                      selectedColor: SystemCorePalette.green.withValues(
                        alpha: 0.18,
                      ),
                      showCheckmark: false,
                      checkmarkColor: SystemCorePalette.green,
                    ),
                ],
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
                onChanged: (value) => setState(
                  () => _profile = profile.copyWith(
                    includeCriticalOutsideInterests: value,
                  ),
                ),
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
              const Text(
                'ЛЕНТА НОВОСТЕЙ',

                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: (_refreshingNews || _loadingNewsCache) ? null : _refreshNews,
                icon: _refreshingNews
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh),
                label: Text(_refreshingNews ? 'ЗАГРУЗКА…' : 'ОБНОВИТЬ ПЕРСОНАЛЬНУЮ ЛЕНТУ'),
              ),
              if (_newsError != null) ...[
                const SizedBox(height: 12),
                Text(_newsError!, style: const TextStyle(color: Colors.orangeAccent)),
              ],
              if (widget.aiEngine != null) ...[
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: (_generatingDigest || _loadingNewsCache || _refreshingNews) ? null : _createDigest,
                  icon: _generatingDigest
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.auto_awesome),
                  label: Text(_generatingDigest ? 'СОЗДАЮ ДАЙДЖЕСТ…' : 'СОЗДАТЬ AI-ДАЙДЖЕСТ'),
                ),
                if (_digestError != null) ...[
                  const SizedBox(height: 8),
                  Text(_digestError!, style: const TextStyle(color: Colors.orangeAccent)),
                ],
                if (_digest != null) ...[
                  const SizedBox(height: 12),
                  Card(
                    color: SystemCorePalette.panel,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: SelectableText(
                        _digest!,
                        style: const TextStyle(color: Colors.white, height: 1.5),
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
              if (_showingCachedNews && !_loadingNewsCache && _articles.isNotEmpty && !_refreshingNews) ...[
                const Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: Text('Показана последняя сохранённая лента; обнови её, чтобы проверить новые публикации.', style: TextStyle(color: SystemCorePalette.muted, fontSize: 12)),
                ),
              ],
              if (!_refreshingNews && _newsError == null && _articles.isEmpty) ...[
                const SizedBox(height: 12),
                const Icon(
                Icons.rss_feed,
                size: 34,
                color: SystemCorePalette.muted,
              ),
              const SizedBox(height: 8),
                Text(
                  profile.topics.isEmpty
                      ? 'Выберите интересы выше — лента останется пустой, пока темы не выбраны.'
                      : 'Нажмите «Обновить», чтобы загрузить свежие материалы по выбранным темам.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: SystemCorePalette.muted, height: 1.4),
                ),
              ],
              for (final article in _articles) ...[
                const SizedBox(height: 10),
                Card(
                  color: SystemCorePalette.panel,
                  child: InkWell(
                    onTap: () => _openArticle(article),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  article.sourceName,
                                  style: const TextStyle(
                                    color: SystemCorePalette.green,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Показывать меньше похожего',
                                onPressed: () => _seeLessOf(article),
                                icon: const Icon(Icons.thumb_down_alt_outlined, size: 19),
                              ),
                              if (article.contentType == NewsContentType.trailer)
                                IconButton(
                                  tooltip: 'Сохранить трейлер в избранное',
                                  onPressed: () => _saveTrailer(article),
                                  icon: const Icon(Icons.favorite_border),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(article.title,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                          if (article.summary.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(article.summary,
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white70, height: 1.35)),
                          ],
                          const SizedBox(height: 8),
                          Text(article.publishedAt.toLocal().toString(),
                              style: const TextStyle(color: SystemCorePalette.muted, fontSize: 11)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
