import 'dart:async';

import 'package:omni_ai/core/ai_engine/models/ai_error.dart';
import 'package:omni_ai/core/ai_engine/models/ai_request.dart';
import 'package:omni_ai/core/ai_engine/models/ai_response.dart';
import 'package:omni_ai/core/ai_engine/providers/ai_provider.dart';
import 'package:omni_ai/core/ai_engine/services/ai_engine.dart';
import 'package:omni_ai/features/run_history/repositories/run_history_repository.dart';
import 'package:omni_ai/features/run_history/services/run_history_recorder.dart';
import 'package:omni_ai/features/system_core/models/system_core_process_state.dart';
import 'package:omni_ai/features/system_core/services/system_core_process_service.dart';

class AIProcessOrchestrator {
  AIProcessOrchestrator({
    required this._engine,
    required SystemCoreProcessService processService,
    required RunHistoryRepository historyRepository,
    ProcessRunIdFactory? runIdFactory,
  }) : _processService = processService,
       _historyRecorder = RunHistoryRecorder(
         processStates: processService.states,
         repository: historyRepository,
         idFactory: runIdFactory,
       );

  final AIEngine _engine;
  final SystemCoreProcessService _processService;
  final RunHistoryRecorder _historyRecorder;
  bool _disposed = false;

  Future<AIResponse> execute(
    AIRequest request, {
    AICancellationToken? cancellationToken,
  }) async {
    if (_disposed) throw StateError('AI process orchestrator is disposed.');
    if (!_processService.state.canStart) {
      throw StateError('A System Core process is already active.');
    }

    final cancellationSubscription = cancellationToken?.cancelled
        .asStream()
        .listen((_) => _processService.cancel());
    AIResponse? response;
    AIEngineException? executionError;
    StackTrace? executionStackTrace;

    try {
      await _processService.start(
        runner: (context) async {
          context.log('AI REQUEST ${request.id}');
          final engineCancellationToken = AICancellationToken();
          unawaited(
            context.cancellationRequested.then(
              (_) => engineCancellationToken.cancel(),
            ),
          );

          try {
            response = await _engine.execute(
              request,
              cancellationToken: engineCancellationToken,
            );
            context.log(
              'AI PROVIDER ${response!.providerId}',
              level: SystemCoreLogLevel.success,
            );
          } on AIEngineException catch (error, stackTrace) {
            executionError = error;
            executionStackTrace = stackTrace;
            if (error.error.code == AIErrorCode.timeout) {
              throw SystemCoreProcessTimeout(error.error.message);
            }
            rethrow;
          }
        },
      );
      await _historyRecorder.flush();

      final error = executionError;
      if (error != null) {
        Error.throwWithStackTrace(error, executionStackTrace!);
      }
      if (_processService.state.status == SystemCoreProcessStatus.cancelled) {
        throw const AIEngineException(
          AIError(
            code: AIErrorCode.cancelled,
            message: 'AI request cancelled.',
          ),
        );
      }
      if (_processService.state.status != SystemCoreProcessStatus.completed ||
          response == null) {
        throw StateError('AI process ended without a response.');
      }
      return response!;
    } finally {
      await cancellationSubscription?.cancel();
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _historyRecorder.dispose();
  }
}
