import 'package:http/http.dart' as http;

import 'network_service.dart';

typedef MirrorProbe = Future<Duration?> Function(Uri mirror);

class MirrorCheckResult {
  const MirrorCheckResult({required this.mirror, required this.ping});

  final Uri mirror;
  final Duration ping;
}

class MirrorResolver {
  const MirrorResolver({
    this.networkService = const NetworkService(),
    MirrorProbe? probe,
  }) : _probeOverride = probe;

  final NetworkService networkService;
  final MirrorProbe? _probeOverride;

  Future<Uri> resolve(Iterable<Uri> mirrors) async {
    final available = await checkAll(mirrors);
    if (available.isEmpty) {
      throw StateError('No available mirrors were found.');
    }
    return available.first.mirror;
  }

  Future<List<Uri>> resolveAll(Iterable<Uri> mirrors) async {
    final results = await checkAll(mirrors);
    return List.unmodifiable(results.map((result) => result.mirror));
  }

  Future<List<MirrorCheckResult>> checkAll(Iterable<Uri> mirrors) async {
    final candidates = mirrors.toSet().toList(growable: false);
    final results = await Future.wait(
      candidates.map((mirror) async => (mirror, await _probe(mirror))),
    );
    results.removeWhere((result) => result.$2 == null);
    results.sort((first, second) => first.$2!.compareTo(second.$2!));
    return List.unmodifiable(
      results.map(
        (result) => MirrorCheckResult(mirror: result.$1, ping: result.$2!),
      ),
    );
  }

  Future<Duration?> _probe(Uri mirror) async {
    final override = _probeOverride;
    try {
      if (override != null) return await override(mirror);

      final stopwatch = Stopwatch()..start();
      final request = http.Request('GET', mirror)
        ..followRedirects = true
        ..maxRedirects = 10;
      final response = await networkService.send(request);
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      return stopwatch.elapsed;
    } on Exception {
      return null;
    }
  }
}
