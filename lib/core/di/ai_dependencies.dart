import 'package:http/http.dart' as http;
import 'package:omni_ai/core/ai_engine/local/local_llama_provider.dart';
import 'package:omni_ai/core/ai_engine/local/local_model_storage.dart';
import 'package:omni_ai/core/ai_engine/local/stored_local_llama_provider.dart';
import 'package:omni_ai/core/ai_engine/providers/ai_execution_mode_store.dart';
import 'package:omni_ai/core/ai_engine/providers/ai_provider.dart';
import 'package:omni_ai/core/ai_engine/providers/routing_ai_provider.dart';
import 'package:omni_ai/core/ai_engine/services/ai_engine.dart';
import 'package:omni_ai/providers/gemini/gemini_api_config.dart';
import 'package:omni_ai/providers/gemini/gemini_api_key_source.dart';
import 'package:omni_ai/providers/gemini/gemini_provider.dart';

/// Builds local and cloud providers behind one explicitly selected AI route.
class AIDependencies {
  factory AIDependencies({
    GeminiApiKeySource? apiKeySource,
    GeminiApiConfig config = const GeminiApiConfig(),
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 30),
    LocalModelStorage? localModelStorage,
    AIExecutionModeStore? modeStore,
    AIProvider? localProvider,
  }) {
    final ownsLocalModelStorage = localModelStorage == null;
    final storage = localModelStorage ?? LocalModelStorage();
    final local = localProvider ?? StoredLocalLlamaProvider(storage: storage);
    final cloud = GeminiProvider(
      apiKeySource: apiKeySource ?? const UnconfiguredGeminiApiKeySource(),
      config: config,
      client: httpClient,
    );
    final router = RoutingAIProvider(
      localProvider: local,
      cloudProvider: cloud,
    );
    return AIDependencies._(
      config: config,
      timeout: timeout,
      localModelStorage: storage,
      ownsLocalModelStorage: ownsLocalModelStorage,
      localProvider: local,
      cloudProvider: cloud,
      router: router,
      modeStore: modeStore ?? SharedPreferencesAIExecutionModeStore(),
    );
  }

  AIDependencies._({
    required this.config,
    required this.timeout,
    required this.localModelStorage,
    required bool ownsLocalModelStorage,
    required this.localProvider,
    required this.cloudProvider,
    required this.router,
    required this.modeStore,
  }) : _ownsLocalModelStorage = ownsLocalModelStorage; // ignore: prefer_initializing_formals

  final GeminiApiConfig config;
  final Duration timeout;
  final LocalModelStorage localModelStorage;
  final bool _ownsLocalModelStorage;
  final AIProvider localProvider;
  final GeminiProvider cloudProvider;
  final RoutingAIProvider router;
  final AIExecutionModeStore modeStore;
  late final AIEngine engine;

  Future<void>? _modeInitialization;
  bool _modeLoaded = false;

  AIExecutionMode get executionMode => router.mode;

  /// Restores the saved destination before the first provider sees a prompt.
  Future<void> restoreExecutionMode() {
    if (_modeLoaded) return Future<void>.value();
    return _modeInitialization ??= _loadExecutionMode();
  }

  Future<void> _loadExecutionMode() async {
    try {
      router.mode = await modeStore.load();
      _modeLoaded = true;
    } finally {
      _modeInitialization = null;
    }
  }

  /// Changes the route explicitly and persists it separately from profile data.
  Future<void> setExecutionMode(AIExecutionMode mode) async {
    await restoreExecutionMode();
    final previousMode = router.mode;
    router.mode = mode;
    try {
      await modeStore.save(mode);
    } on Object {
      router.mode = previousMode;
      rethrow;
    }
  }

  Future<void> dispose() async {
    final local = localProvider;
    if (local is StoredLocalLlamaProvider) {
      await local.dispose();
    } else if (local is LocalLlamaProvider) {
      await local.dispose();
    }
    cloudProvider.close();
    if (_ownsLocalModelStorage) localModelStorage.dispose();
  }
}
