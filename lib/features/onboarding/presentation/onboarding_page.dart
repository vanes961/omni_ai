import 'package:flutter/material.dart';
import 'package:omni_ai/features/dashboard/presentation/dashboard_page.dart';

import '../data/user_preferences.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key, this.preferencesStore});

  final UserPreferencesStore? preferencesStore;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  int _currentStep = 0;
  final UserPreferences _prefs = UserPreferences();
  late final UserPreferencesStore _preferencesStore;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _preferencesStore =
        widget.preferencesStore ?? SharedPreferencesUserPreferencesStore();
  }

  final List<String> _stepTitles = [
    '01 // СФЕРЫ ИНТЕРЕСОВ',
    '02 // ИЗБРАННЫЕ ТАЙТЛЫ',
    '03 // ПРЕДПОЧИТАЕМЫЕ ОЗВУЧКИ',
    '04 // ИСТОЧНИКИ (TELEGRAM)',
    '05 // ИИ-СИНХРОНИЗАЦИЯ',
  ];

  final List<List<String>> _stepOptions = [
    ['Фильмы', 'Сериалы', 'Аниме', 'Игры', 'Технологии', 'Школа', 'Здоровье'],
    [
      'Cyberpunk',
      'Игра Престолов',
      'Атака Титанов',
      'Ведьмак',
      'Marvel',
      'Гарри Поттер',
    ],
    ['RHS', 'Anilibria', 'StudioBand', 'LostFilm', 'HDRezka', 'Оригинал'],
    ['Life Free Hub', 'Игромания', 'Технологии', 'Аниме Новости', 'Кинопоиск'],
  ];

  void _nextStep() {
    if (_currentStep < 4) {
      setState(() => _currentStep++);
    } else {
      _saveAndLaunch();
    }
  }

  Future<void> _saveAndLaunch() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      await _preferencesStore.save(_prefs);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (context) => DashboardPage(preferences: _prefs),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось сохранить профиль: $error')),
      );
    }
  }

  void _toggleOption(String option) {
    setState(() {
      final current = switch (_currentStep) {
        0 => _prefs.categories,
        1 => _prefs.favoriteTitles,
        2 => _prefs.voiceDubbing,
        3 => _prefs.tgChannels,
        _ => null,
      };
      if (current == null) return;
      current.contains(option) ? current.remove(option) : current.add(option);
    });
  }

  bool _isSelected(String option) {
    final current = switch (_currentStep) {
      0 => _prefs.categories,
      1 => _prefs.favoriteTitles,
      2 => _prefs.voiceDubbing,
      3 => _prefs.tgChannels,
      _ => null,
    };
    return current?.contains(option) ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F13),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(
                value: (_currentStep + 1) / 5,
                backgroundColor: Colors.white10,
                color: const Color(0xFF00FF87),
              ),
              const SizedBox(height: 24),
              Text(
                _stepTitles[_currentStep],
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF00FF87),
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: _currentStep < 4
                    ? Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: _stepOptions[_currentStep].map((option) {
                          final selected = _isSelected(option);
                          return FilterChip(
                            label: Text(option),
                            selected: selected,
                            selectedColor: const Color(0xFF6C5CE7),
                            checkmarkColor: Colors.white,
                            onSelected: (_) => _toggleOption(option),
                          );
                        }).toList(),
                      )
                    : const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.psychology,
                            size: 72,
                            color: Color(0xFF00FF87),
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Формирование локального вектора...',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Все данные зашифрованы и обработаны локально на устройстве.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
              ),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6C5CE7),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _isSaving ? null : _nextStep,
                  child: Text(
                    _isSaving
                        ? 'СОХРАНЕНИЕ...'
                        : _currentStep == 4
                        ? 'ЗАПУСТИТЬ ЭКОСИСТЕМУ'
                        : 'ПРОДОЛЖИТЬ',
                    style: const TextStyle(
                      fontSize: 15,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
