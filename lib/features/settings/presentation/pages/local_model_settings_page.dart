import 'package:flutter/material.dart';
import 'package:omni_ai/core/ai_engine/local/local_model_storage.dart';
import 'package:omni_ai/features/system_core/presentation/system_core_palette.dart';

class LocalModelSettingsPage extends StatefulWidget {
  const LocalModelSettingsPage({required this.storage, super.key});

  final LocalModelStorage storage;

  @override
  State<LocalModelSettingsPage> createState() => _LocalModelSettingsPageState();
}

class _LocalModelSettingsPageState extends State<LocalModelSettingsPage> {
  static const _model = LocalModelCatalog.qwen3Small;

  bool _checking = true;
  bool _downloading = false;
  bool _installed = false;
  int _receivedBytes = 0;
  int? _totalBytes;
  String? _error;
  String? _status;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
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
    if (_downloading) return;
    setState(() {
      _downloading = true;
      _receivedBytes = 0;
      _totalBytes = null;
      _error = null;
      _status = 'Загрузка модели… Не закрывайте приложение надолго.';
    });
    final task = widget.storage.download(
      _model,
      onProgress: (received, total) {
        if (!mounted) return;
        setState(() {
          _receivedBytes = received;
          _totalBytes = total;
        });
      },
    );
    try {
      await task;
      if (!mounted) return;
      setState(() {
        _installed = true;
        _status = 'Модель загружена и проверена по размеру файла.';
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Загрузка не завершена: $error';
        _status = null;
      });
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _delete() async {
    if (_downloading) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить локальную модель?'),
        content: const Text(
          'Файл модели будет удалён из хранилища приложения. '
          'Его можно будет загрузить снова.',
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
    final total = _totalBytes ?? _model.expectedBytesApprox;
    final progress = total > 0 ? (_receivedBytes / total).clamp(0.0, 1.0) : 0.0;
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
          'Файл модели загружается отдельно от APK и хранится в закрытой '
          'папке приложения. Само наличие файла ещё не означает, что '
          'генерация уже подключена к основному чату.',
          style: TextStyle(color: SystemCorePalette.muted, fontSize: 12),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: SystemCorePalette.panel,
            border: Border.all(color: Colors.white12),
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
                'Формат GGUF · Q4_K_M · требуется интернет для загрузки',
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
                            : 'Модель не загружена',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              if (_downloading) ...[
                const SizedBox(height: 14),
                LinearProgressIndicator(
                  value: progress,
                  color: SystemCorePalette.green,
                  backgroundColor: Colors.white12,
                ),
                const SizedBox(height: 8),
                Text(
                  '${_formatBytes(_receivedBytes)} / ${_formatBytes(total)}',
                  style: const TextStyle(
                    color: SystemCorePalette.muted,
                    fontSize: 11,
                  ),
                ),
              ],
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
                  onPressed: _checking || _downloading || _installed
                      ? null
                      : _download,
                  icon: _downloading
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download),
                  label: Text(
                    _downloading ? 'ЗАГРУЗКА…' : 'ЗАГРУЗИТЬ МОДЕЛЬ',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const ValueKey('local-model-delete-button'),
                  onPressed: _checking || _downloading || !_installed
                      ? null
                      : _delete,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('УДАЛИТЬ ФАЙЛ'),
                ),
              ),
              if (!_downloading && !_checking) ...[
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
          'Важно: размер проверяется по данным сервера и ожидаемому объёму, '
          'но криптографическая подпись модели пока не проверяется. '
          'Загрузка не использует облачный AI API.',
          style: TextStyle(color: SystemCorePalette.muted, fontSize: 11),
        ),
      ],
    );
  }
}
