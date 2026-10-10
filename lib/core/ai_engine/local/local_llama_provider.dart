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

  static const providerId = 'local-llama';

  @override
  String get id => providerId;

  Future<void> loadModel({int? gpuLayers}) async {
    _ensureNotDisposed();
    if (_loading) {
      throw StateError('Local model is already loading.');
    }
    if (!await modelFile.exists()) {
      throw FileSystemException(
        'Local model file does not exist.',
        modelFile.path,
      );
    }

    _loading = true;
    try {
      if (await _controller.isModelLoaded()) return;
      await _controller.loadModel(
        modelPath: modelFile.path,
        threads: threads,
        contextSize: contextSize,
        gpuLayers: gpuLayers,
      );
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
    if (!await _controller.isModelLoaded()) {
      throw const AIEngineException(
        AIError(
          code: AIErrorCode.invalidRequest,
          message: 'Local model is not loaded.',
        ),
      );
    }
    if (cancellationToken.isCancelled) {
      throw const AIEngineException(
        AIError(
          code: AIErrorCode.cancelled,
          message: 'AI request cancelled.',
        ),
      );
    }

    var cancelled = false;
    var generationFinished = false;
    final cancellationListener = cancellationToken.cancelled.then(
      (_) async {
      if (generationFinished) return;
      cancelled = true;
      try {
        await _controller.stop();
      } on Object {
        // Cancellation is best-effort; preserve the generation result/error.
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
        metadata: {
          'modelPath': modelFile.path,
          'local': true,
        },
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
      // This listener intentionally remains pending until cancellation.
      unawaited(cancellationListener);
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
