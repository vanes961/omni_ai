import 'dart:async';

import '../models/ai_request.dart';
import '../models/ai_response.dart';

class AICancellationToken {
  AICancellationToken();

  final Completer<void> _completer = Completer<void>();

  bool get isCancelled => _completer.isCompleted;
  Future<void> get cancelled => _completer.future;

  void cancel() {
    if (!_completer.isCompleted) {
      _completer.complete();
    }
  }
}

abstract interface class AIProvider {
  String get id;

  Future<AIResponse> complete(
    AIRequest request, {
    required AICancellationToken cancellationToken,
  });
}
