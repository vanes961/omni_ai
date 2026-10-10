import 'dart:async';
import 'dart:io';

import 'package:llama_flutter_android/llama_flutter_android.dart';

import '../models/ai_error.dart';
import '../models/ai_request.dart';
import '../models/ai_response.dart';
import '../providers/ai_provider.dart';

/// Local inference adapter for an already-downloaded GGUF model.
///
/// The model lifecycle is explicit: call [loadModel] before sending requests.
/// No prompt is sent to a remote service by this provider.
class LocalLlamaProvider implements AIProvider {
  LocalLlamaProvider({
    required this.modelFile,
    LlamaController? controller,
    this.threads = 4,
    this.contextSize = 2048,
    this.maxTokens = 256,
    this.temperature = 0.7,
  }) : _controller = controller ?? LlamaController();

  final File modelFile;
  final LlamaController _controller;
  final int threads;
  final int contextSize;
  final int maxTokens;
  final double temperature;

  bool _disposed = false;
  bool _loading = false;
  bool _generating = false;

  static const providerId = 'local-llama';

  @override
  String get id => providerId;

  Future<void> loadModel({int? gpuLayers}) async {
    _ensureNotDisposed();
    if (_loading) {
      throw StateError('Local model is already loading.');
    }
    if (_generating) {
      throw StateError('Cannot load a model while generation is running.');
    }

    // Set the lock before the first await so concurrent callers cannot both
    // pass the guard while the filesystem check is in progress.
    _loading = true;
    try {
      if (!await modelFile.exists()) {
        throw FileSystemException(
          'Local model file does not exist.',
          modelFile.path,
        );
      }
      _ensureNotDisposed();
      if (await _controller.isModelLoaded()) return;
      _ensureNotDisposed();
      await _controller.loadModel(
        modelPath: modelFile.path,
        threads: threads,
        contextSize: contextSize,
        gpuLayers: gpuLayers,
      );
      _ensureNotDisposed();
    } finally {
      _loading = false;
    }
  }

  @override
  Future<AIResponse> complete(
    AIRequest request, {
    required AICancellationToken cancellationToken,
  }) async {
    _ensureNotDisposed();
    if (_loading) {
      throw StateError('Cannot generate while the local model is loading.');
    }
    if (_generating) {
      throw const AIEngineException(
        AIError(
          code: AIErrorCode.provider,
          message: 'A local generation is already in progress.',
          retryable: true,
        ),
      );
    }
    if (!await _controller.isModelLoaded()) {
      throw const AIEngineException(
        AIError(
          code: AIErrorCode.invalidRequest,
          message: 'Local model is not loaded.',
        ),
      );
    }
    _ensureNotDisposed();
    // Recheck after the await: another request may have entered while the
    // controller was checking its state.
    if (_generating || _loading) {
      throw const AIEngineException(
        AIError(
          code: AIErrorCode.provider,
          message: 'Local inference is already in progress.',
          retryable: true,
        ),
      );
    }
    if (cancellationToken.isCancelled) {
      throw const AIEngineException(
        AIError(code: AIErrorCode.cancelled, message: 'AI request cancelled.'),
      );
    }
    _generating = true;

    var cancelled = false;
    var generationFinished = false;
    final cancellationListener = _listenForCancellation(
      cancellationToken,
      () => generationFinished,
      () {
        cancelled = true;
      },
    );

    final prompt = <String>[
      if (request.systemInstruction?.trim().isNotEmpty ?? false)
        'System instruction:\n${request.systemInstruction!.trim()}',
      'User:\n${request.prompt.trim()}',
      'Assistant:',
    ].join('\n\n');

    final output = StringBuffer();
    try {
      await for (final token in _controller.generate(
        prompt: prompt,
        maxTokens: maxTokens,
        temperature: temperature,
      )) {
        if (cancellationToken.isCancelled) break;
        output.write(token);
      }
      if (cancelled || cancellationToken.isCancelled) {
        throw const AIEngineException(
          AIError(
            code: AIErrorCode.cancelled,
            message: 'AI request cancelled.',
          ),
        );
      }

      final text = output.toString().trim();
      if (text.isEmpty) {
        throw const AIEngineException(
          AIError(
            code: AIErrorCode.provider,
            message: 'Local model returned an empty response.',
            retryable: true,
          ),
        );
      }

      return AIResponse(
        requestId: request.id,
        text: text,
        providerId: id,
        generatedAt: DateTime.now(),
        metadata: {'modelPath': modelFile.path, 'local': true},
      );
    } on AIEngineException {
      rethrow;
    } on Object catch (error) {
      if (cancellationToken.isCancelled) {
        throw const AIEngineException(
          AIError(
            code: AIErrorCode.cancelled,
            message: 'AI request cancelled.',
          ),
        );
      }
      throw AIEngineException(
        AIError(
          code: AIErrorCode.provider,
          message: 'Local inference failed: $error',
          retryable: true,
        ),
      );
    } finally {
      generationFinished = true;
      _generating = false;
      // This listener intentionally remains pending until cancellation.
      unawaited(cancellationListener);
    }
  }

  Future<void> _listenForCancellation(
    AICancellationToken cancellationToken,
    bool Function() isGenerationFinished,
    void Function() markCancelled,
  ) async {
    await cancellationToken.cancelled;
    if (isGenerationFinished()) return;
    markCancelled();
    try {
      await _controller.stop();
    } on Object {
      // Cancellation is best-effort; preserve the generation result/error.
    }
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('Local LLM provider has been disposed.');
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _controller.dispose();
  }
}
