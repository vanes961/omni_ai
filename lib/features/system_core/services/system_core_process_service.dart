import 'dart:async';

import 'package:omni_ai/features/system_core/models/system_core_process_state.dart';

typedef SystemCoreProcessRunner =
    Future<void> Function(SystemCoreProcessContext context);

class SystemCoreProcessContext {
  const SystemCoreProcessContext._({
    required this.cancellationRequested,
    required this._isCancellationRequested,
    required this._writeLog,
  });

  final Future<void> cancellationRequested;
  final bool Function() _isCancellationRequested;
  final void Function(String message, SystemCoreLogLevel level) _writeLog;

  bool get isCancellationRequested => _isCancellationRequested();

  void log(
    String message, {
    SystemCoreLogLevel level = SystemCoreLogLevel.neutral,
  }) {
    _writeLog(message, level);
  }

  void throwIfCancellationRequested() {
    if (isCancellationRequested) throw const _ProcessCancelled();
  }
}

class SystemCoreProcessService {
  SystemCoreProcessService({
    SystemCoreProcessRunner? runner,
    DateTime Function()? clock,
  }) : _runner = runner ?? _runDemoProcess,
       _clock = clock ?? DateTime.now,
       _state = SystemCoreProcessState.initial(clock: clock ?? DateTime.now);

  final SystemCoreProcessRunner _runner;
  final DateTime Function() _clock;
  final StreamController<SystemCoreProcessState> _states =
      StreamController<SystemCoreProcessState>.broadcast(sync: true);

  SystemCoreProcessState _state;
  Completer<void>? _cancellation;
  int _runGeneration = 0;
  bool _disposed = false;

  SystemCoreProcessState get state => _state;
  Stream<SystemCoreProcessState> get states => _states.stream;

  Future<void> start() async {
    if (_disposed || !_state.canStart) return;

    final runGeneration = ++_runGeneration;
    final cancellation = Completer<void>();
    _cancellation = cancellation;
    _transition(
      SystemCoreProcessStatus.starting,
      'AUTO-PROCESS STARTING...',
      SystemCoreLogLevel.neutral,
      clearError: true,
    );

    await Future<void>.delayed(Duration.zero);
    if (runGeneration != _runGeneration ||
        _state.status != SystemCoreProcessStatus.starting) {
      return;
    }

    _transition(
      SystemCoreProcessStatus.running,
      'AUTO-PROCESS INITIALIZED',
      SystemCoreLogLevel.success,
    );

    final context = SystemCoreProcessContext._(
      cancellationRequested: cancellation.future,
      isCancellationRequested: () => cancellation.isCompleted,
      writeLog: (message, level) {
        if (_disposed ||
            runGeneration != _runGeneration ||
            _state.status != SystemCoreProcessStatus.running) {
          return;
        }
        _appendLog(message, level);
      },
    );

    try {
      await Future.any<void>([
        Future<void>.sync(() => _runner(context)),
        cancellation.future.then<void>((_) => throw const _ProcessCancelled()),
      ]);
      if (runGeneration != _runGeneration) return;
      if (_state.status != SystemCoreProcessStatus.cancelled) {
        _transition(
          SystemCoreProcessStatus.completed,
          'AUTO-PROCESS COMPLETED',
          SystemCoreLogLevel.success,
        );
      }
    } on _ProcessCancelled {
      // cancel() already records the terminal state and journal event.
    } catch (error) {
      if (runGeneration == _runGeneration &&
          _state.status != SystemCoreProcessStatus.cancelled) {
        final message = error.toString();
        _transition(
          SystemCoreProcessStatus.failed,
          'AUTO-PROCESS FAILED: $message',
          SystemCoreLogLevel.error,
          errorMessage: message,
        );
      }
    }
  }

  void cancel() {
    if (_disposed || !_state.isActive) return;

    final cancellation = _cancellation;
    _runGeneration++;
    if (cancellation != null && !cancellation.isCompleted) {
      cancellation.complete();
    }
    _transition(
      SystemCoreProcessStatus.cancelled,
      'AUTO-PROCESS CANCELLED',
      SystemCoreLogLevel.accent,
    );
  }

  Future<void> dispose() async {
    if (_disposed) return;
    cancel();
    _disposed = true;
    await _states.close();
  }

  void _appendLog(String message, SystemCoreLogLevel level) {
    _state = _state.addEvent(
      status: _state.status,
      entry: SystemCoreLogEntry(
        timestamp: _clock(),
        message: message,
        level: level,
      ),
    );
    _states.add(_state);
  }

  void _transition(
    SystemCoreProcessStatus status,
    String message,
    SystemCoreLogLevel level, {
    String? errorMessage,
    bool clearError = false,
  }) {
    _state = _state.addEvent(
      status: status,
      entry: SystemCoreLogEntry(
        timestamp: _clock(),
        message: message,
        level: level,
      ),
      errorMessage: errorMessage,
      clearError: clearError,
    );
    if (!_disposed) _states.add(_state);
  }
}

Future<void> _runDemoProcess(SystemCoreProcessContext context) async {
  await Future<void>.delayed(const Duration(milliseconds: 120));
  context.throwIfCancellationRequested();
  context.log('NEURAL CORE SYNCHRONIZED', level: SystemCoreLogLevel.neutral);

  await Future<void>.delayed(const Duration(milliseconds: 120));
  context.throwIfCancellationRequested();
  context.log('TASK QUEUE: READY', level: SystemCoreLogLevel.success);
}

class _ProcessCancelled implements Exception {
  const _ProcessCancelled();
}
