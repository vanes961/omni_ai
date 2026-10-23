import 'dart:async';

import 'package:flutter/material.dart';
import 'package:omni_ai/core/ai_engine/local/local_model_storage.dart';
import 'package:omni_ai/core/ai_engine/models/ai_request.dart';
import 'package:omni_ai/core/ai_engine/providers/ai_provider.dart';
import 'package:omni_ai/core/ai_engine/providers/routing_ai_provider.dart';
import 'package:omni_ai/core/di/ai_dependencies.dart';
import 'package:omni_ai/features/system_core/presentation/system_core_palette.dart';

class LocalModelSettingsPage extends StatefulWidget {
  const LocalModelSettingsPage({
    required this.storage,
    this.aiDependencies,
    super.key,
  });

  final LocalModelStorage storage;
  final AIDependencies? aiDependencies;

  @override
  State<LocalModelSettingsPage> createState() => _LocalModelSettingsPageState();
}

class _LocalModelSettingsPageState extends State<LocalModelSettingsPage> {
  static const _model = LocalModelCatalog.qwen3Small;

  bool _checking = true;
  bool _installing = false;
  bool _installed = false;
  String? _error;
  String? _status;
  AIExecutionMode _executionMode = AIExecutionMode.local;
  bool _modeLoading = false;
  bool _modeSaving = false;
  String? _modeError;
  final TextEditingController _cloudKeyController = TextEditingController();
  bool _hasCloudKey = false;
  bool _keyLoading = false;
  bool _keySaving = false;
  bool _cloudTesting = false;
  String? _keyMessage;

  @override
  void dispose() {
    _cloudKeyController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _refreshStatus();
    if (widget.aiDependencies != null) {
      _modeLoading = true;
      _keyLoading = true;
      unawaited(_restoreExecutionMode());
      unawaited(_restoreCloudKeyStatus());
    }
  }

  Future<void> _restoreExecutionMode() async {
    try {
      await widget.aiDependencies!.restoreExecutionMode();
      if (!mounted) return;
      setState(() => _executionMode = widget.aiDependencies!.executionMode);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _modeError = 'Не удалось восстановить режим AI: $error');
    } finally {
      if (mounted) setState(() => _modeLoading = false);
    }
  }

  Future<void> _restoreCloudKeyStatus() async {
    try {
      final hasKey = await widget.aiDependencies!.hasCloudApiKey;
      if (!mounted) return;
      setState(() => _hasCloudKey = hasKey);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _keyMessage = 'Не удалось проверить ключ: $error');
    } finally {
      if (mounted) setState(() => _keyLoading = false);
    }
  }

  Future<void> _saveCloudKey() async {
    final dependencies = widget.aiDependencies;
    final key = _cloudKeyController.text.trim();
    if (dependencies == null || key.isEmpty || _keySaving) return;
    setState(() {
      _keySaving = true;
      _keyMessage = null;
    });
    try {
      await dependencies.saveCloudApiKey(key);
      if (!mounted) return;
      _cloudKeyController.clear();
      setState(() {
        _hasCloudKey = true;
        _keyMessage = 'Ключ сохранён в защищённом хранилище устройства.';
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _keyMessage = 'Не удалось сохранить ключ: $error');
    } finally {
      if (mounted) setState(() => _keySaving = false);
    }
  }

  Future<void> _testCloudConnection() async {
    final dependencies = widget.aiDependencies;
    if (dependencies == null || _cloudTesting) return;
    setState(() {
      _cloudTesting = true;
      _keyMessage = 'Проверяем реальный ответ OpenRouter…';
    });
    try {
      final response = await dependencies.cloudProvider
          .complete(
            const AIRequest(
              id: 'openrouter-connection-check',
              prompt: 'Ответь одним словом: OK',
            ),
            cancellationToken: AICancellationToken(),
          )
          .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      setState(
        () => _keyMessage =
            'Облако отвечает (${response.providerId}, '
            '${response.metadata['model'] ?? 'модель не указана'}).',
      );
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _keyMessage = 'Проверка облака не прошла: $error');
    } finally {
      if (mounted) setState(() => _cloudTesting = false);
    }
  }

  Future<void> _deleteCloudKey() async {
    final dependencies = widget.aiDependencies;
    if (dependencies == null || _keySaving) return;
    setState(() {
      _keySaving = true;
      _keyMessage = null;
    });
    try {
      await dependencies.deleteCloudApiKey();
      if (!mounted) return;
      setState(() {
        _hasCloudKey = false;
        _keyMessage = 'Облачный ключ удалён с устройства.';
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _keyMessage = 'Не удалось удалить ключ: $error');
    } finally {
      if (mounted) setState(() => _keySaving = false);
    }
  }

  Future<void> _selectExecutionMode(AIExecutionMode mode) async {
    final dependencies = widget.aiDependencies;
    if (dependencies == null || _modeLoading || _modeSaving) return;
    final previousMode = _executionMode;
    setState(() {
      _executionMode = mode;
      _modeSaving = true;
      _modeError = null;
    });
    try {
      await dependencies.setExecutionMode(mode);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _executionMode = previousMode;
          _modeError = 'Не удалось сохранить режим AI: $error';
        });
      }
    } finally {
      if (mounted) setState(() => _modeSaving = false);
    }
  }

  Future<void> _refreshStatus() async {
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final installed = await widget.storage.isDownloaded(_model);
      if (!mounted) return;
      setState(() {
        _installed = installed;
        _checking = false;
        _status = installed ? 'Модель уже находится на устройстве.' : null;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _error = 'Не удалось проверить файлы модели: $error';
      });
    }
  }

  Future<void> _download() async {
    if (_installing) return;
    setState(() {
      _installing = true;
      _error = null;
      _status = _installed
          ? 'Проверяем целостность установленной модели…'
          : 'Скачиваем модель. Нужны стабильный интернет и около 500 МБ свободного места.';
    });
    try {
      await widget.storage.download(_model);
      if (!mounted) return;
      setState(() {
        _installed = true;
        _status = 'Модель скачана и проверена по размеру и SHA-256.';
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Не удалось скачать или проверить модель: $error';
        _status = null;
      });
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }

  Future<void> _delete() async {
    if (_installing) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить локальную модель?'),
        content: const Text(
          'Файл модели будет удалён из хранилища приложения. '
          'Для повторной установки потребуется скачать около 500 МБ.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('ОТМЕНА'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('УДАЛИТЬ'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.storage.delete(_model);
      if (!mounted) return;
      setState(() {
        _installed = false;
        _status = 'Файл модели удалён.';
        _error = null;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Не удалось удалить модель: $error');
    }
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} ГБ';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} КБ';
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const ValueKey('local-model-settings-page'),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      children: [
        const Text(
          '05 // ON-DEVICE INFERENCE',
          style: TextStyle(
            color: SystemCorePalette.muted,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'ЛОКАЛЬНАЯ МОДЕЛЬ',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Модель скачивается отдельно один раз и хранится в закрытой папке приложения. '
          'Обычные обновления приложения её не содержат и не удаляют.',
          style: TextStyle(color: SystemCorePalette.muted, fontSize: 12),
        ),
        if (widget.aiDependencies != null) ...[
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: SystemCorePalette.panel,
              border: Border.all(
                color: SystemCorePalette.border.withValues(alpha: 0.55),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'РЕЖИМ ВЫПОЛНЕНИЯ AI',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                SegmentedButton<AIExecutionMode>(
                  segments: const [
                    ButtonSegment(
                      value: AIExecutionMode.automatic,
                      icon: Icon(Icons.auto_awesome),
                      label: Text('Авто'),
                    ),
                    ButtonSegment(
                      value: AIExecutionMode.local,
                      icon: Icon(Icons.phone_android),
                      label: Text('Local AI'),
                    ),
                    ButtonSegment(
                      value: AIExecutionMode.cloud,
                      icon: Icon(Icons.cloud_outlined),
                      label: Text('Cloud AI'),
                    ),
                  ],
                  selected: {_executionMode},
                  onSelectionChanged: _modeLoading || _modeSaving
                      ? null
                      : (selection) =>
                            unawaited(_selectExecutionMode(selection.first)),
                ),
                const SizedBox(height: 10),
                Text(
                  switch (_executionMode) {
                    AIExecutionMode.automatic =>
                      'Авто: команды приложения обрабатываются локально, рекомендации и сложные вопросы направляются в облако. При сбое облака выполняется попытка локального ответа.',
                    AIExecutionMode.local =>
                      'Локальный режим: запросы не отправляются облачному провайдеру. Сначала установите встроенную модель ниже.',
                    AIExecutionMode.cloud =>
                      'Облачный режим: используется OpenRouter (openrouter/free). Нужен API-ключ; он не должен вшиваться в APK.',
                  },
                  style: const TextStyle(
                    color: SystemCorePalette.muted,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'ОБЛАЧНЫЙ ДОСТУП // OPENROUTER',
                  style: TextStyle(
                    color: SystemCorePalette.green,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey('openrouter-api-key-field'),
                  controller: _cloudKeyController,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'Личный API-ключ OpenRouter',
                    hintText: 'sk-or-…',
                    helperText:
                        'Создаётся в аккаунте OpenRouter. Не отправляйте ключ в чат.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        key: const ValueKey('save-openrouter-key-button'),
                        onPressed: _keyLoading || _keySaving
                            ? null
                            : _saveCloudKey,
                        icon: _keySaving
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.lock_outline),
                        label: const Text('СОХРАНИТЬ КЛЮЧ'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      key: const ValueKey('delete-openrouter-key-button'),
                      tooltip: 'Удалить ключ',
                      onPressed: !_hasCloudKey || _keySaving
                          ? null
                          : _deleteCloudKey,
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    key: const ValueKey('test-openrouter-connection-button'),
                    onPressed: !_hasCloudKey || _cloudTesting || _keyLoading
                        ? null
                        : _testCloudConnection,
                    icon: _cloudTesting
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_done_outlined),
                    label: Text(
                      _cloudTesting
                          ? 'ПРОВЕРКА ОБЛАКА…'
                          : 'ПРОВЕРИТЬ ОБЛАЧНЫЙ ИИ',
                    ),
                  ),
                ),
                Text(
                  _keyLoading
                      ? 'Проверяем сохранённый ключ…'
                      : _hasCloudKey
                      ? 'Ключ настроен на этом устройстве.'
                      : 'Ключ не настроен.',
                  style: const TextStyle(
                    color: SystemCorePalette.muted,
                    fontSize: 11,
                  ),
                ),
                if (_keyMessage != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _keyMessage!,
                    style: const TextStyle(
                      color: SystemCorePalette.green,
                      fontSize: 11,
                    ),
                  ),
                ],
                if (_modeLoading || _modeSaving) ...[
                  const SizedBox(height: 10),
                  const LinearProgressIndicator(color: SystemCorePalette.green),
                ],
                if (_modeError != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _modeError!,
                    style: const TextStyle(
                      color: Colors.orangeAccent,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: SystemCorePalette.panel,
            border: Border.all(
              color: SystemCorePalette.border.withValues(alpha: 0.55),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.memory,
                color: SystemCorePalette.green,
                size: 28,
              ),
              const SizedBox(height: 12),
              Text(
                _model.displayName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Ориентировочный размер: '
                '${_formatBytes(_model.expectedBytesApprox)}',
                style: const TextStyle(
                  color: SystemCorePalette.muted,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Формат GGUF · Q4_K_M · отдельная загрузка · после установки работает офлайн',
                style: TextStyle(color: SystemCorePalette.muted, fontSize: 11),
              ),
              const SizedBox(height: 16),
              if (_checking)
                const LinearProgressIndicator(color: SystemCorePalette.green)
              else
                Row(
                  children: [
                    Icon(
                      _installed ? Icons.check_circle : Icons.info_outline,
                      color: _installed
                          ? SystemCorePalette.green
                          : SystemCorePalette.muted,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _installed
                            ? 'Файл модели найден'
                            : 'Модель не установлена',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              if (_status != null) ...[
                const SizedBox(height: 12),
                Text(
                  _status!,
                  style: const TextStyle(
                    color: SystemCorePalette.green,
                    fontSize: 11,
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: Colors.orangeAccent,
                    fontSize: 11,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const ValueKey('local-model-download-button'),
                  onPressed: _checking || _installing ? null : _download,
                  icon: _installing
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download),
                  label: Text(
                    _installing
                        ? 'ЗАГРУЗКА / ПРОВЕРКА…'
                        : _installed
                        ? 'ПОВТОРНО ПРОВЕРИТЬ МОДЕЛЬ'
                        : 'СКАЧАТЬ ЛОКАЛЬНУЮ МОДЕЛЬ',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const ValueKey('local-model-delete-button'),
                  onPressed: _checking || _installing || !_installed
                      ? null
                      : _delete,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('УДАЛИТЬ ФАЙЛ'),
                ),
              ),
              if (!_installing && !_checking) ...[
                const SizedBox(height: 4),
                TextButton.icon(
                  onPressed: _refreshStatus,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('ПРОВЕРИТЬ СНОВА'),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'Загружаемый файл проверяется по ожидаемому размеру и SHA-256. '
          'После первой загрузки интернет для локального ИИ не требуется.',
          style: TextStyle(color: SystemCorePalette.muted, fontSize: 11),
        ),
      ],
    );
  }
}
