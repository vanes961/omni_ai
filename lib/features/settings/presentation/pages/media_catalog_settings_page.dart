import 'dart:async';

import 'package:flutter/material.dart';
import 'package:omni_ai/features/media/services/media_catalog_token_store.dart';
import 'package:omni_ai/features/system_core/presentation/system_core_palette.dart';

class MediaCatalogSettingsPage extends StatefulWidget {
  const MediaCatalogSettingsPage({this.tokenStore, super.key});

  final MediaCatalogTokenStore? tokenStore;

  @override
  State<MediaCatalogSettingsPage> createState() =>
      _MediaCatalogSettingsPageState();
}

class _MediaCatalogSettingsPageState extends State<MediaCatalogSettingsPage> {
  late final MediaCatalogTokenStore _tokenStore;
  final TextEditingController _tokenController = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _hasToken = false;
  bool _obscureToken = true;
  String? _status;

  @override
  void initState() {
    super.initState();
    _tokenStore = widget.tokenStore ?? SecureMediaCatalogTokenStore();
    unawaited(_restoreTokenStatus());
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _restoreTokenStatus() async {
    try {
      final token = await _tokenStore.readToken();
      if (!mounted) return;
      setState(() => _hasToken = token?.isNotEmpty == true);
    } on Object catch (error) {
      if (!mounted) return;
      setState(
        () => _status = 'Не удалось прочитать защищённое хранилище: $error',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveToken() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty || _saving) {
      setState(
        () => _status = 'Вставьте TMDB Read Access Token перед сохранением.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _status = null;
    });
    try {
      await _tokenStore.saveToken(token);
      if (!mounted) return;
      _tokenController.clear();
      setState(() {
        _hasToken = true;
        _status =
            'Токен сохранён в защищённом хранилище устройства. Вернитесь в «Медиа» и выполните поиск.';
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _status = 'Не удалось сохранить токен: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteToken() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _status = null;
    });
    try {
      await _tokenStore.deleteToken();
      if (!mounted) return;
      setState(() {
        _hasToken = false;
        _status = 'Токен удалён с устройства. Онлайн-поиск каталога отключён.';
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _status = 'Не удалось удалить токен: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const ValueKey('media-catalog-settings-page'),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'МЕДИАКАТАЛОГ',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Для реального поиска фильмов, сериалов и аниме OMNI AI использует TMDB. Токен хранится только в защищённом хранилище этого устройства.',
            style: TextStyle(color: SystemCorePalette.muted, height: 1.5),
          ),
          const SizedBox(height: 14),
          const SelectableText(
            'Получить токен: https://www.themoviedb.org/settings/api',
            style: TextStyle(color: SystemCorePalette.green, height: 1.4),
          ),
          const SizedBox(height: 20),
          TextField(
            key: const ValueKey('tmdb-token-field'),
            controller: _tokenController,
            obscureText: _obscureToken,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'TMDB Read Access Token',
              hintText: 'Вставьте токен',
              suffixIcon: IconButton(
                tooltip: _obscureToken ? 'Показать токен' : 'Скрыть токен',
                onPressed: () => setState(() => _obscureToken = !_obscureToken),
                icon: Icon(
                  _obscureToken
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const ValueKey('save-tmdb-token'),
              onPressed: _loading || _saving ? null : _saveToken,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.lock_outline),
              label: const Text('Сохранить токен'),
            ),
          ),
          const SizedBox(height: 10),
          if (_loading)
            const LinearProgressIndicator(minHeight: 2)
          else
            Row(
              children: [
                Icon(
                  _hasToken ? Icons.check_circle_outline : Icons.info_outline,
                  color: _hasToken
                      ? SystemCorePalette.green
                      : SystemCorePalette.muted,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _hasToken
                        ? 'Токен настроен на этом устройстве'
                        : 'Токен не настроен — онлайн-поиск не работает',
                    style: const TextStyle(color: SystemCorePalette.muted),
                  ),
                ),
                if (_hasToken)
                  TextButton(
                    key: const ValueKey('delete-tmdb-token'),
                    onPressed: _saving ? null : _deleteToken,
                    child: const Text('Удалить'),
                  ),
              ],
            ),
          if (_status != null) ...[
            const SizedBox(height: 14),
            Text(
              _status!,
              key: const ValueKey('tmdb-token-status'),
              style: const TextStyle(
                color: SystemCorePalette.green,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
