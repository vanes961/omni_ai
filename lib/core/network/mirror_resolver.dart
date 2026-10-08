import 'network_service.dart';

typedef MirrorProbe = Future<Duration?> Function(Uri mirror);

class MirrorResolver {
  const MirrorResolver({
    this.networkService = const NetworkService(),
    MirrorProbe? probe,
  }) : _probeOverride = probe;

  final NetworkService networkService;
  final MirrorProbe? _probeOverride;

  Future<Uri> resolve(Iterable<Uri> mirrors) async {
    final available = await resolveAll(mirrors);
    if (available.isEmpty) {
      throw StateError('No available mirrors were found.');
    }
    return available.first;
  }

  Future<List<Uri>> resolveAll(Iterable<Uri> mirrors) async {
    final candidates = mirrors.toSet().toList(growable: false);
    final results = await Future.wait(
      candidates.map((mirror) async => (mirror, await _probe(mirror))),
    );
    results.removeWhere((result) => result.$2 == null);
    results.sort((first, second) => first.$2!.compareTo(second.$2!));
    return List.unmodifiable(results.map((result) => result.$1));
  }

  Future<Duration?> _probe(Uri mirror) async {
    final override = _probeOverride;
    if (override != null) return override(mirror);

    final stopwatch = Stopwatch()..start();
    try {
      final response = await networkService.get(mirror);
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      return stopwatch.elapsed;
    } on Exception {
      return null;
    } finally {
      stopwatch.stop();
    }
  }
}
