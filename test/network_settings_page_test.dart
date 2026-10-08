import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omni_ai/core/network/network_service.dart';
import 'package:omni_ai/core/network/proxy_config.dart';
import 'package:omni_ai/features/onboarding/data/user_preferences.dart';
import 'package:omni_ai/features/settings/presentation/pages/network_settings_page.dart';

void main() {
  testWidgets('saves proxy settings and displays mirror health', (
    tester,
  ) async {
    final keyValueStore = _MemoryStringStore();
    final preferencesStore = SharedPreferencesUserPreferencesStore(
      store: keyValueStore,
    );
    final preferences = UserPreferences();
    ProxyConfig? appliedProxy;
    final client = MockClient((request) async => http.Response('', 200));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NetworkSettingsPage(
            preferences: preferences,
            preferencesStore: preferencesStore,
            mirrors: [Uri.https('mirror.example', '/')],
            networkServiceFactory: (proxyConfig) {
              appliedProxy = proxyConfig;
              return NetworkService(client: client);
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('auto-mirror-switch')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('proxy-enabled-switch')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('proxy-type-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SOCKS5').last);
    await tester.pumpAndSettle();

    final hostField = find.byKey(const ValueKey('proxy-host-field'));
    await tester.ensureVisible(hostField);
    await tester.enterText(hostField, 'proxy.example');
    await tester.pumpAndSettle();
    final portField = find.byKey(const ValueKey('proxy-port-field'));
    await tester.ensureVisible(portField);
    await tester.enterText(portField, '9050');
    await tester.pumpAndSettle();

    final checkButton = find.byKey(const ValueKey('check-network-button'));
    await tester.ensureVisible(checkButton);
    await tester.tap(checkButton);
    await tester.pumpAndSettle();

    expect(appliedProxy?.type, ProxyType.socks5);
    expect(appliedProxy?.host, 'proxy.example');
    expect(appliedProxy?.port, 9050);
    expect(find.text('mirror.example'), findsOneWidget);
    expect(find.text('ДОСТУПНО'), findsOneWidget);
    expect(find.textContaining(' ms'), findsOneWidget);

    final restored = await preferencesStore.load();
    expect(restored?.proxyEnabled, isTrue);
    expect(restored?.proxyType, 'socks5');
    expect(restored?.proxyHost, 'proxy.example');
    expect(restored?.proxyPort, 9050);
    expect(restored?.autoMirrorEnabled, isFalse);
  });

  testWidgets('shows an unavailable transport instead of throwing', (
    tester,
  ) async {
    final preferences = UserPreferences()
      ..proxyEnabled = true
      ..proxyType = 'socks5'
      ..proxyHost = 'proxy.example';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NetworkSettingsPage(
            preferences: preferences,
            preferencesStore: SharedPreferencesUserPreferencesStore(
              store: _MemoryStringStore(),
            ),
            mirrors: [Uri.https('mirror.example', '/')],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final checkButton = find.byKey(const ValueKey('check-network-button'));
    await tester.ensureVisible(checkButton);
    await tester.tap(checkButton);
    await tester.pumpAndSettle();

    expect(find.textContaining('not implemented yet'), findsOneWidget);
  });
}

class _MemoryStringStore implements UserPreferencesStringStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }
}
