import 'package:http/http.dart' as http;
import 'package:omni_ai/core/ai_engine/local/local_model_storage.dart';
import 'package:omni_ai/core/ai_engine/providers/ai_execution_mode_store.dart';
import 'package:omni_ai/core/di/ai_dependencies.dart';
import 'package:omni_ai/features/run_history/data/shared_preferences_run_history_repository.dart';
import 'package:omni_ai/features/run_history/repositories/run_history_repository.dart';
import 'package:omni_ai/features/system_core/services/ai_process_orchestrator.dart';
import 'package:omni_ai/features/system_core/services/system_core_process_service.dart';
import 'package:omni_ai/providers/gemini/gemini_api_config.dart';
import 'package:omni_ai/providers/gemini/gemini_api_key_source.dart';

/// The application's manual dependency-composition root.
///
/// This object does not start an AI request automatically. Resources passed
/// in by callers remain caller-owned and are not disposed by this object.
class AppDependencies {
  factory AppDependencies({
    GeminiApiKeySource? apiKeySource,
    GeminiApiConfig geminiConfig = const GeminiApiConfig(),
    http.Client? httpClient,
    Duration aiTimeout = const Duration(seconds: 30),
    SystemCoreProcessService? processService,
    RunHistoryRepository? runHistoryRepository,
    LocalModelStorage? localModelStorage,
    AIExecutionModeStore? aiExecutionModeStore,
  }) {
    final ownsProcessService = processService == null;
    final ownsHistoryRepository = runHistoryRepository == null;
    final ownsLocalModelStorage = localModelStorage == null;
    final storage = localModelStorage ?? LocalModelStorage();
    final ai = AIDependencies(
      apiKeySource: apiKeySource,
      config: geminiConfig,
      httpClient: httpClient,
      timeout: aiTimeout,
      localModelStorage: storage,
      modeStore: aiExecutionModeStore,
    );
    return AppDependencies._(
      ai: ai,
      processService: processService ?? SystemCoreProcessService(),
      historyRepository:
          runHistoryRepository ?? SharedPreferencesRunHistoryRepository(),
      localModelStorage: storage,
      ownsProcessService: ownsProcessService,
      ownsHistoryRepository: ownsHistoryRepository,
      ownsLocalModelStorage: ownsLocalModelStorage,
    );
  }

  AppDependencies._({
    required this.ai,
    required this.processService,
    required this.historyRepository,
    required this._ownsProcessService,
    required this._ownsHistoryRepository,
    required this.localModelStorage,
    required this._ownsLocalModelStorage,
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
  final bool _ownsProcessService;
  final bool _ownsHistoryRepository;
  final LocalModelStorage localModelStorage;
  final bool _ownsLocalModelStorage;
  late final AIProcessOrchestrator orchestrator;

  Future<void> dispose() async {
    await orchestrator.dispose();
    if (_ownsProcessService) await processService.dispose();
    if (_ownsHistoryRepository) await historyRepository.dispose();
    await ai.dispose();
    if (_ownsLocalModelStorage) localModelStorage.dispose();
  }
}
