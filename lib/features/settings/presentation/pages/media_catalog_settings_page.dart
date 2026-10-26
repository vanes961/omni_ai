import 'dart:async';

import 'package:flutter/material.dart';
import 'package:omni_ai/features/media/services/media_catalog_token_store.dart';
import 'package:omni_ai/features/media/services/poiskkino_api_key_store.dart';
import 'package:omni_ai/features/system_core/presentation/system_core_palette.dart';

class MediaCatalogSettingsPage extends StatefulWidget {
  const MediaCatalogSettingsPage({this.tokenStore, this.poiskKinoKeyStore, super.key});

  final MediaCatalogTokenStore? tokenStore;
  final PoiskKinoApiKeyStore? poiskKinoKeyStore;

  @override
  State<MediaCatalogSettingsPage> createState() => _MediaCatalogSettingsPageState();
}

class _MediaCatalogSettingsPageState extends State<MediaCatalogSettingsPage> {
  late final MediaCatalogTokenStore _tokenStore;
  late final PoiskKinoApiKeyStore _poiskKinoKeyStore;
  final TextEditingController _tokenController = TextEditingController();
  final TextEditingController _poiskKinoController = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _hasToken = false;
  bool _hasPoiskKinoKey = false;
  bool _obscureToken = true;
  bool _obscurePoiskKinoKey = true;
  String? _status;

  @override
  void initState() {
    super.initState();
    _tokenStore = widget.tokenStore ?? SecureMediaCatalogTokenStore();
    _poiskKinoKeyStore = widget.poiskKinoKeyStore ?? SecurePoiskKinoApiKeyStore();
    unawaited(_restoreTokenStatus());
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _poiskKinoController.dispose();
    super.dispose();
  }

  Future<void> _restoreTokenStatus() async {
    try {
      final values = await Future.wait<String?>([
        _tokenStore.readToken(),
        _poiskKinoKeyStore.readApiKey(),
      ]);
      if (!mounted) return;
      setState(() {
        _hasToken = values[0]?.isNotEmpty == true;
        _hasPoiskKinoKey = values[1]?.isNotEmpty == true;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _status = 'Не удалось прочитать защищённое хранилище: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveToken() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty || _saving) {
      setState(() => _status = 'Вставьте TMDB Read Access Token перед сохранением.');
      return;
    }
    setState(() { _saving = true; _status = null; });
    try {
      await _tokenStore.saveToken(token);
      if (!mounted) return;
      _tokenController.clear();
      setState(() {
        _hasToken = true;
        _status = 'TMDB-токен сохранён в защищённом хранилище устройства. Вернитесь в «Медиа» и выполните поиск.';
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
    setState(() { _saving = true; _status = null; });
    try {
      await _tokenStore.deleteToken();
      if (!mounted) return;
      setState(() {
        _hasToken = false;
        _status = 'TMDB-токен удалён с устройства.';
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _status = 'Не удалось удалить токен: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _savePoiskKinoKey() async {
    final key = _poiskKinoController.text.trim();
    if (key.isEmpty || _saving) {
      setState(() => _status = 'Вставьте API-ключ ПоискКино перед сохранением.');
      return;
    }
    setState(() { _saving = true; _status = null; });
    try {
      await _poiskKinoKeyStore.saveApiKey(key);
      if (!mounted) return;
      _poiskKinoController.clear();
      setState(() {
        _hasPoiskKinoKey = true;
        _status = 'Ключ ПоискКино сохранён в защищённом хранилище устройства.';
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _status = 'Не удалось сохранить ключ ПоискКино: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deletePoiskKinoKey() async {
    if (_saving) return;
    setState(() { _saving = true; _status = null; });
    try {
      await _poiskKinoKeyStore.deleteApiKey();
      if (!mounted) return;
      setState(() {
        _hasPoiskKinoKey = false;
        _status = 'Ключ ПоискКино удалён с устройства.';
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _status = 'Не удалось удалить ключ ПоискКино: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _tokenStatus({required bool configured, required String label, required String deleteKey, required VoidCallback onDelete}) {
    return Row(children: [
      Icon(configured ? Icons.check_circle_outline : Icons.info_outline,
        color: configured ? SystemCorePalette.green : SystemCorePalette.muted, size: 18),
      const SizedBox(width: 8),
      Expanded(child: Text(label, style: const TextStyle(color: SystemCorePalette.muted))),
      if (configured) TextButton(
        key: ValueKey(deleteKey), onPressed: _saving ? null : onDelete,
        child: const Text('Удалить')),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const ValueKey('media-catalog-settings-page'),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('МЕДИАКАТАЛОГ', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
        const SizedBox(height: 8),
        const Text('TMDB — основной источник метаданных. ПоискКино используется как дополнительный источник карточек фильмов и сериалов. Ключи хранятся только в защищённом хранилище этого устройства.', style: TextStyle(color: SystemCorePalette.muted, height: 1.5)),
        const SizedBox(height: 14),
        const SelectableText('TMDB: https://www.themoviedb.org/settings/api', style: TextStyle(color: SystemCorePalette.green, height: 1.4)),
        const SizedBox(height: 12),
        TextField(key: const ValueKey('tmdb-token-field'), controller: _tokenController, obscureText: _obscureToken, autocorrect: false, enableSuggestions: false,
          decoration: InputDecoration(labelText: 'TMDB Read Access Token', hintText: 'Вставьте токен',
            suffixIcon: IconButton(tooltip: _obscureToken ? 'Показать токен' : 'Скрыть токен', onPressed: () => setState(() => _obscureToken = !_obscureToken),
              icon: Icon(_obscureToken ? Icons.visibility_outlined : Icons.visibility_off_outlined)),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)))),
        const SizedBox(height: 10),
        SizedBox(width: double.infinity, child: FilledButton.icon(key: const ValueKey('save-tmdb-token'),
          onPressed: _loading || _saving ? null : _saveToken,
          icon: const Icon(Icons.lock_outline), label: const Text('Сохранить токен'))),
        const SizedBox(height: 8),
        _tokenStatus(configured: _hasToken, label: _hasToken ? 'TMDB настроен' : 'TMDB не настроен', deleteKey: 'delete-tmdb-token', onDelete: _deleteToken),
        const Divider(height: 28),
        const Text('ПОИСККИНО', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 1.0)),
        const SizedBox(height: 8),
        const Text('Дополнительные карточки фильмов и сериалов. API-ключ выдаётся сервисом ПоискКино; источник метаданных не предоставляет ссылки на воспроизведение.', style: TextStyle(color: SystemCorePalette.muted, height: 1.5)),
        const SizedBox(height: 12),
        TextField(key: const ValueKey('poiskkino-api-key-field'), controller: _poiskKinoController, obscureText: _obscurePoiskKinoKey, autocorrect: false, enableSuggestions: false,
          decoration: InputDecoration(labelText: 'PoiskKino API Key', hintText: 'Вставьте API-ключ',
            suffixIcon: IconButton(tooltip: _obscurePoiskKinoKey ? 'Показать ключ' : 'Скрыть ключ', onPressed: () => setState(() => _obscurePoiskKinoKey = !_obscurePoiskKinoKey),
              icon: Icon(_obscurePoiskKinoKey ? Icons.visibility_outlined : Icons.visibility_off_outlined)),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)))),
        const SizedBox(height: 10),
        SizedBox(width: double.infinity, child: FilledButton.icon(key: const ValueKey('save-poiskkino-api-key'),
          onPressed: _loading || _saving ? null : _savePoiskKinoKey,
          icon: const Icon(Icons.lock_outline), label: const Text('Сохранить ключ ПоискКино'))),
        const SizedBox(height: 8),
        _tokenStatus(configured: _hasPoiskKinoKey, label: _hasPoiskKinoKey ? 'Ключ ПоискКино настроен' : 'Ключ ПоискКино не настроен', deleteKey: 'delete-poiskkino-api-key', onDelete: _deletePoiskKinoKey),
        if (_loading) const Padding(padding: EdgeInsets.only(top: 10), child: LinearProgressIndicator(minHeight: 2)),
        if (_status != null) ...[
          const SizedBox(height: 14),
          Text(_status!, key: const ValueKey('tmdb-token-status'), style: const TextStyle(color: SystemCorePalette.green, height: 1.4)),
        ],
      ]),
    );
  }
}
