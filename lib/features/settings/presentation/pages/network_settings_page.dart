import 'dart:async';

import 'package:flutter/material.dart';
import 'package:omni_ai/core/network/mirror_resolver.dart';
import 'package:omni_ai/core/network/network_service.dart';
import 'package:omni_ai/core/network/proxy_config.dart';
import 'package:omni_ai/features/media/data/torrserver_client.dart';
import 'package:omni_ai/features/onboarding/data/user_preferences.dart';
import 'package:omni_ai/features/system_core/presentation/system_core_palette.dart';

typedef NetworkSettingsServiceFactory =
    NetworkService Function(ProxyConfig? proxyConfig);

class NetworkSettingsPage extends StatefulWidget {
  NetworkSettingsPage({
    required this.preferences,
    required this.preferencesStore,
    List<Uri>? mirrors,
    this.networkServiceFactory,
    super.key,
  }) : mirrors = mirrors ?? defaultMirrors;

  static final List<Uri> defaultMirrors = List.unmodifiable([
    Uri.https('one.one.one.one', '/cdn-cgi/trace'),
    Uri.https('connectivitycheck.gstatic.com', '/generate_204'),
    Uri.https('www.google.com', '/generate_204'),
  ]);

  final UserPreferences preferences;
  final UserPreferencesStore preferencesStore;
  final List<Uri> mirrors;
  final NetworkSettingsServiceFactory? networkServiceFactory;

  @override
  State<NetworkSettingsPage> createState() => _NetworkSettingsPageState();
}

class _NetworkSettingsPageState extends State<NetworkSettingsPage> {
  late final TextEditingController _hostController = TextEditingController(
    text: widget.preferences.proxyHost,
  );
  late final TextEditingController _portController = TextEditingController(
    text: widget.preferences.proxyPort.toString(),
  );
  late final TextEditingController _torrServerController =
      TextEditingController(text: widget.preferences.torrServerUrl);
  Future<void> _saveQueue = Future<void>.value();
  bool _isChecking = false;
  MirrorCheckResult? _currentResult;
  String? _statusMessage;
  bool? _isAvailable;
  bool _isCheckingTorrServer = false;
  bool? _torrServerAvailable;
  String? _torrServerMessage;

  ProxyType get _proxyType => ProxyType.values.firstWhere(
    (type) => type.name == widget.preferences.proxyType,
    orElse: () => ProxyType.http,
  );

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _torrServerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preferences = widget.preferences;
    return ListView(
      key: const ValueKey('network-settings-page'),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      children: [
        const Text(
          '04 // NETWORK & PROXY',
          style: TextStyle(
            color: SystemCorePalette.muted,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'СЕТЬ И ДОСТУП',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 20),
        _sectionTitle('МАРШРУТИЗАЦИЯ'),
        _settingsGroup(
          child: SwitchListTile(
            key: const ValueKey('auto-mirror-switch'),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14),
            title: const Text('Авто-выбор зеркал'),
            subtitle: const Text(
              'Проверять доступность и выбирать узел с минимальным ping',
              style: TextStyle(color: SystemCorePalette.muted, fontSize: 11),
            ),
            value: preferences.autoMirrorEnabled,
            activeThumbColor: SystemCorePalette.green,
            onChanged: (value) => _updatePreferences(() {
              preferences.autoMirrorEnabled = value;
            }),
          ),
        ),
        const SizedBox(height: 20),
        _sectionTitle('PROXY / TUNNEL'),
        _settingsGroup(
          child: Column(
            children: [
              SwitchListTile(
                key: const ValueKey('proxy-enabled-switch'),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                title: const Text('Использовать Proxy/Tunnel'),
                value: preferences.proxyEnabled,
                activeThumbColor: SystemCorePalette.green,
                onChanged: (value) => _updatePreferences(() {
                  preferences.proxyEnabled = value;
                }),
              ),
              if (preferences.proxyEnabled) ...[
                const Divider(height: 1, color: SystemCorePalette.border.withValues(alpha: 0.55)),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      DropdownButtonFormField<ProxyType>(
                        key: const ValueKey('proxy-type-dropdown'),
                        initialValue: _proxyType,
                        decoration: const InputDecoration(
                          labelText: 'Тип прокси',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: ProxyType.values
                            .map(
                              (type) => DropdownMenuItem(
                                value: type,
                                child: Text(_proxyTypeLabel(type)),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (type) {
                          if (type == null) return;
                          _updatePreferences(() {
                            preferences.proxyType = type.name;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextField(
                              key: const ValueKey('proxy-host-field'),
                              controller: _hostController,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Хост',
                                hintText: 'proxy.example.org',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              onChanged: (value) => _updatePreferences(() {
                                preferences.proxyHost = value.trim();
                              }),
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 112,
                            child: TextField(
                              key: const ValueKey('proxy-port-field'),
                              controller: _portController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Порт',
                                hintText: '1080',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              onChanged: (value) {
                                final port = int.tryParse(value);
                                if (port == null || port < 1 || port > 65535) {
                                  return;
                                }
                                _updatePreferences(() {
                                  preferences.proxyPort = port;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        _sectionTitle('МЕДИА-СЕРВЕР / TORRSERVER'),
        _settingsGroup(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Адрес внешнего TorrServer',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey('torrserver-url-field'),
                  controller: _torrServerController,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.done,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'URL сервера',
                    hintText: 'http://192.168.1.20:8090',
                    helperText:
                        'Можно указать IP домашней сети. HTTP не шифрует трафик: не открывайте сервер в интернет. Не добавляйте логин или пароль в URL.',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (value) => _updatePreferences(() {
                    preferences.torrServerUrl = value.trim();
                  }),
                ),
                const SizedBox(height: 10),
                if (_torrServerMessage != null) ...[
                  Text(
                    _torrServerMessage!,
                    key: const ValueKey('torrserver-status-message'),
                    style: TextStyle(
                      color: _torrServerAvailable == true
                          ? SystemCorePalette.green
                          : _torrServerAvailable == false
                          ? SystemCorePalette.red
                          : SystemCorePalette.muted,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    key: const ValueKey('check-torrserver-button'),
                    onPressed: _isCheckingTorrServer
                        ? null
                        : _checkTorrServerConnection,
                    icon: _isCheckingTorrServer
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.dns_outlined, size: 18),
                    label: const Text('Проверить TorrServer'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        _sectionTitle('СОСТОЯНИЕ СЕТИ'),
        _NetworkStatus(
          checking: _isChecking,
          result: _currentResult,
          isAvailable: _isAvailable,
          message: _statusMessage,
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 46,
          child: FilledButton.icon(
            key: const ValueKey('check-network-button'),
            onPressed: _isChecking ? null : _checkConnection,
            icon: _isChecking
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.network_check, size: 18),
            label: const Text('Проверить соединение'),
          ),
        ),
      ],
    );
  }

  void _updatePreferences(VoidCallback update) {
    setState(update);
    final snapshot = UserPreferences.fromJson(widget.preferences.toJson());
    _saveQueue = _saveQueue
        .catchError((Object _) {})
        .then((_) => widget.preferencesStore.save(snapshot))
        .catchError((Object error) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Не удалось сохранить настройки: $error')),
          );
        });
  }

  Future<void> _checkConnection() async {
    final preferences = widget.preferences;
    final port = int.tryParse(_portController.text);
    if (preferences.proxyEnabled &&
        (preferences.proxyHost.isEmpty ||
            port == null ||
            port < 1 ||
            port > 65535)) {
      setState(() {
        _currentResult = null;
        _isAvailable = false;
        _statusMessage = 'УКАЖИТЕ КОРРЕКТНЫЕ ХОСТ И ПОРТ ПРОКСИ';
      });
      return;
    }
    if (widget.mirrors.isEmpty) {
      setState(() {
        _currentResult = null;
        _isAvailable = false;
        _statusMessage = 'ЗЕРКАЛА НЕ НАСТРОЕНЫ';
      });
      return;
    }

    setState(() {
      _isChecking = true;
      _currentResult = null;
      _isAvailable = null;
      _statusMessage = 'ПРОВЕРКА ДОСТУПНОСТИ';
    });

    NetworkService? service;
    try {
      final proxyConfig = preferences.proxyEnabled
          ? ProxyConfig(
              type: _proxyType,
              host: preferences.proxyHost,
              port: port!,
            )
          : null;
      service =
          widget.networkServiceFactory?.call(proxyConfig) ??
          (proxyConfig == null
              ? const NetworkService()
              : NetworkService.withProxy(proxyConfig: proxyConfig));
      final mirrors = preferences.autoMirrorEnabled
          ? widget.mirrors
          : [widget.mirrors.first];
      final results = await MirrorResolver(
        networkService: service,
      ).checkAll(mirrors);
      if (!mounted) return;
      setState(() {
        _currentResult = results.isEmpty ? null : results.first;
        _isAvailable = results.isNotEmpty;
        _statusMessage = results.isEmpty
            ? 'НЕТ ДОСТУПНЫХ ЗЕРКАЛ'
            : 'ПРОВЕРКА ЗАВЕРШЕНА';
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _currentResult = null;
        _isAvailable = false;
        _statusMessage = error.toString();
      });
    } finally {
      service?.close();
      if (mounted) setState(() => _isChecking = false);
    }
  }

  Future<void> _checkTorrServerConnection() async {
    final endpoint = _torrServerController.text.trim();
    setState(() {
      _isCheckingTorrServer = true;
      _torrServerAvailable = null;
      _torrServerMessage = 'ПРОВЕРКА TORRSERVER';
    });

    final client = TorrServerClient();
    try {
      final result = await client.checkConnection(endpoint);
      if (!mounted) return;
      setState(() {
        _torrServerAvailable = result.isAvailable;
        _torrServerMessage = result.message;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _torrServerAvailable = false;
        _torrServerMessage = 'Не удалось проверить TorrServer';
      });
    } finally {
      client.close();
      if (mounted) setState(() => _isCheckingTorrServer = false);
    }
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: SystemCorePalette.green,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _settingsGroup({required Widget child}) {
    return Material(
      color: SystemCorePalette.panel,
      child: DecoratedBox(
        decoration: BoxDecoration(border: Border.all(color: SystemCorePalette.border.withValues(alpha: 0.55))),
        child: child,
      ),
    );
  }
}

class _NetworkStatus extends StatelessWidget {
  const _NetworkStatus({
    required this.checking,
    required this.result,
    required this.isAvailable,
    required this.message,
  });

  final bool checking;
  final MirrorCheckResult? result;
  final bool? isAvailable;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final stateColor = isAvailable == null
        ? SystemCorePalette.muted
        : isAvailable!
        ? SystemCorePalette.green
        : SystemCorePalette.red;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SystemCorePalette.panel,
        border: Border.all(color: SystemCorePalette.border.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isAvailable == true
                    ? Icons.check_circle_outline
                    : isAvailable == false
                    ? Icons.error_outline
                    : Icons.circle_outlined,
                color: stateColor,
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  checking ? 'ПРОВЕРКА...' : (message ?? 'ОЖИДАНИЕ ПРОВЕРКИ'),
                  style: TextStyle(
                    color: stateColor,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 18,
            runSpacing: 12,
            children: [
              _StatusValue(
                label: 'ТЕКУЩЕЕ ЗЕРКАЛО',
                value: result?.mirror.host ?? '—',
              ),
              _StatusValue(
                label: 'PING',
                value: result == null
                    ? '—'
                    : '${result!.ping.inMilliseconds} ms',
              ),
              _StatusValue(
                label: 'ДОСТУПНОСТЬ',
                value: isAvailable == null
                    ? 'НЕ ПРОВЕРЕНА'
                    : isAvailable!
                    ? 'ДОСТУПНО'
                    : 'НЕТ СВЯЗИ',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusValue extends StatelessWidget {
  const _StatusValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: SystemCorePalette.muted, fontSize: 9),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

String _proxyTypeLabel(ProxyType type) => switch (type) {
  ProxyType.http => 'HTTP',
  ProxyType.socks5 => 'SOCKS5',
  ProxyType.mtproto => 'MTProto',
};
