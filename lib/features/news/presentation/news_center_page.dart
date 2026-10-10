import 'dart:async';

import 'package:flutter/material.dart';
import 'package:omni_ai/features/news/data/news_interest_repository.dart';
import 'package:omni_ai/features/news/data/shared_preferences_news_interest_repository.dart';
import 'package:omni_ai/features/news/models/news_interest_profile.dart';
import 'package:omni_ai/features/system_core/presentation/system_core_palette.dart';

class NewsCenterPage extends StatefulWidget {
  const NewsCenterPage({super.key, this.repository});

  final NewsInterestRepository? repository;

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

  @override
  void initState() {
    super.initState();
    _ownsRepository = widget.repository == null;
    _repository =
        widget.repository ?? SharedPreferencesNewsInterestRepository();
    _profileFuture = _repository.load();
  }

  @override
  void dispose() {
    if (_ownsRepository) unawaited(_repository.dispose());
    super.dispose();
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

  void _toggleTopic(String topic, bool selected) {
    final profile = _profile;
    if (profile == null) return;
    final topics = profile.topics.toSet();
    if (selected) {
      topics.add(topic);
    } else {
      topics.remove(topic);
    }
    setState(() => _profile = profile.copyWith(topics: topics.toList()));
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
                'ЛЕНТА НОВОСТЕЙ',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 10),
              const Icon(
                Icons.rss_feed,
                size: 34,
                color: SystemCorePalette.muted,
              ),
              const SizedBox(height: 8),
              const Text(
                'Подключение источников — следующий шаг. Здесь пока нет загруженных новостей; выдуманные или нерелевантные материалы не подставляются.',
                textAlign: TextAlign.center,
                style: TextStyle(color: SystemCorePalette.muted, height: 1.4),
              ),
            ],
          );
        },
      ),
    );
  }
}
