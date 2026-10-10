import 'package:http/http.dart' as http;
import 'package:omni_ai/core/ai_engine/services/ai_engine.dart';
import 'package:omni_ai/providers/gemini/gemini_api_config.dart';
import 'package:omni_ai/providers/gemini/gemini_api_key_source.dart';
import 'package:omni_ai/providers/gemini/gemini_provider.dart';

/// Builds the provider-specific dependencies used by the AI engine.
class AIDependencies {
  factory AIDependencies({
    GeminiApiKeySource? apiKeySource,
    GeminiApiConfig config = const GeminiApiConfig(),
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 30),
  }) {
    final provider = GeminiProvider(
      apiKeySource: apiKeySource ?? const EnvironmentGeminiApiKeySource(),
      config: config,
      client: httpClient,
    );
    return AIDependencies._(
      provider: provider,
      config: config,
      timeout: timeout,
    );
  }

  AIDependencies._({
    required this.provider,
    required this.config,
    required this.timeout,
  }) : engine = AIEngine(provider: provider, timeout: timeout);

  final GeminiApiConfig config;
  final Duration timeout;
  final GeminiProvider provider;
  final AIEngine engine;

  void dispose() {
    provider.close();
  }
}
