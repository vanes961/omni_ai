import 'package:http/http.dart' as http;
import 'package:omni_ai/core/di/ai_dependencies.dart';
import 'package:omni_ai/features/run_history/data/shared_preferences_run_history_repository.dart';
import 'package:omni_ai/features/run_history/repositories/run_history_repository.dart';
import 'package:omni_ai/features/system_core/services/ai_process_orchestrator.dart';
import 'package:omni_ai/features/system_core/services/system_core_process_service.dart';
import 'package:omni_ai/providers/gemini/gemini_api_config.dart';
import 'package:omni_ai/providers/gemini/gemini_api_key_source.dart';

/// The application's manual dependency-composition root.
///
/// This object does not start an AI request automatically.
class AppDependencies {
  factory AppDependencies({
    GeminiApiKeySource? apiKeySource,
    GeminiApiConfig geminiConfig = const GeminiApiConfig(),
    http.Client? httpClient,
    Duration aiTimeout = const Duration(seconds: 30),
    SystemCoreProcessService? processService,
    RunHistoryRepository? runHistoryRepository,
  }) {
    final ai = AIDependencies(
      apiKeySource: apiKeySource,
      config: geminiConfig,
      httpClient: httpClient,
      timeout: aiTimeout,
    );
    return AppDependencies._(
      ai: ai,
      processService: processService ?? SystemCoreProcessService(),
      historyRepository:
          runHistoryRepository ?? SharedPreferencesRunHistoryRepository(),
    );
  }

  AppDependencies._({
    required this.ai,
    required this.processService,
    required this.historyRepository,
  }) {
    orchestrator = AIProcessOrchestrator(
      engine: ai.engine,
      processService: processService,
      historyRepository: historyRepository,
    );
  }

  final AIDependencies ai;
  final SystemCoreProcessService processService;
  final RunHistoryRepository historyRepository;
  late final AIProcessOrchestrator orchestrator;

  Future<void> dispose() async {
    await orchestrator.dispose();
    await processService.dispose();
    await historyRepository.dispose();
    ai.dispose();
  }
}
