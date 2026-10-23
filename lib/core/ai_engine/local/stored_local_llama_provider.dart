import 'dart:io';

import '../models/ai_error.dart';
import '../models/ai_request.dart';
import '../models/ai_response.dart';
import '../providers/ai_provider.dart';
import '../providers/ai_streaming_provider.dart';
import 'local_llama_provider.dart';
import 'local_model_storage.dart';

/// Lazily initializes the already-installed GGUF model for local requests.
///
/// The model is kept in app-private storage across app updates. A normal
/// application update must never require the model to be bundled in its APK.
class StoredLocalLlamaProvider implements AIProvider, AIStreamingProvider {
  StoredLocalLlamaProvider({
    required this.storage,
    this.model = LocalModelCatalog.qwen3Small,
    this.autoInstallBundledModel = false,
    LocalLlamaProvider Function(File modelFile)? providerFactory,
  }) : _providerFactory =
           providerFactory ?? ((file) => LocalLlamaProvider(modelFile: file));

  final LocalModelStorage storage;
  final LocalModelSpec model;
  final bool autoInstallBundledModel;
  final LocalLlamaProvider Function(File modelFile) _providerFactory;

  LocalLlamaProvider? _provider;
  Future<LocalLlamaProvider>? _initializing;
  bool _disposed = false;

  @override
  String get id => LocalLlamaProvider.providerId;

  @override
  Future<AIResponse> complete(
    AIRequest request, {
    required AICancellationToken cancellationToken,
  }) async {
    _ensureNotDisposed();
    if (cancellationToken.isCancelled) {
      throw const AIEngineException(
        AIError(code: AIErrorCode.cancelled, message: 'AI request cancelled.'),
      );
    }
    final provider = await _readyProvider();
    _ensureNotDisposed();
    return provider.complete(request, cancellationToken: cancellationToken);
  }

  @override
  Future<AIResponse> completeStreaming(
    AIRequest request, {
    required AICancellationToken cancellationToken,
    required void Function(String token) onToken,
  }) async {
    _ensureNotDisposed();
    if (cancellationToken.isCancelled) {
      throw const AIEngineException(
        AIError(code: AIErrorCode.cancelled, message: 'AI request cancelled.'),
      );
    }
    final provider = await _readyProvider();
    _ensureNotDisposed();
    return provider.completeStreaming(
      request,
      cancellationToken: cancellationToken,
      onToken: onToken,
    );
  }

  Future<LocalLlamaProvider> _readyProvider() {
    _ensureNotDisposed();
    final ready = _provider;
    if (ready != null) return Future.value(ready);
    return _initializing ??= _initialize();
  }

  Future<LocalLlamaProvider> _initialize() async {
    LocalLlamaProvider? provider;
    try {
      var isInstalled = await storage.isValid(model);
      _ensureNotDisposed();
      if (!isInstalled && autoInstallBundledModel) {
        await storage.installBundled(model);
        _ensureNotDisposed();
        isInstalled = true;
      }
      if (!isInstalled) {
        throw AIEngineException(
          AIError(
            code: AIErrorCode.invalidRequest,
            message:
                'Локальная модель не установлена. Откройте настройки локального ИИ и скачайте модель.',
          ),
        );
      }
      final file = await storage.modelFile(model);
      _ensureNotDisposed();
      provider = _providerFactory(file);
      await provider.loadModel();
      if (_disposed) {
        await provider.dispose();
        throw StateError('Local LLM provider has been disposed.');
      }
      _provider = provider;
      return provider;
    } catch (_) {
      if (provider != null && !identical(provider, _provider)) {
        await provider.dispose();
      }
      rethrow;
    } finally {
      _initializing = null;
    }
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('Stored local LLM provider has been disposed.');
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final initializing = _initializing;
    if (initializing != null) {
      try {
        await initializing;
      } on Object {
        // Initialization checks the disposed flag and cleans itself up.
      }
    }
    final provider = _provider;
    _provider = null;
    if (provider != null) await provider.dispose();
  }
}
