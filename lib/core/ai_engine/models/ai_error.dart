enum AIErrorCode {
  cancelled,
  timeout,
  provider,
  invalidRequest,
  unknown,
}

class AIError {
  const AIError({
    required this.code,
    required this.message,
    this.retryable = false,
  });

  final AIErrorCode code;
  final String message;
  final bool retryable;
}

class AIEngineException implements Exception {
  const AIEngineException(this.error);

  final AIError error;

  @override
  String toString() => 'AIEngineException(${error.code.name}): ${error.message}';
}
