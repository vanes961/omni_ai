import 'package:omni_ai/features/media/data/torrserver_endpoint.dart';
import 'package:omni_ai/features/media/domain/media_hub_contracts.dart';

/// Builds the documented TorrServer /stream URL for a validated magnet link.
///
/// This only resolves a URL; it does not claim that the torrent is available
/// or that a particular file index is a video. The caller should obtain the
/// file list from the server/provider and pass the chosen index explicitly.
class TorrServerStreamResolver {
  const TorrServerStreamResolver();

  Uri resolve({
    required String endpoint,
    required Uri magnetUri,
    int? fileIndex,
    bool play = true,
  }) {
    final config = TorrServerEndpoint.tryParse(endpoint);
    if (config == null) {
      throw ArgumentError.value(
        endpoint,
        'endpoint',
        'Must be a valid HTTP(S) TorrServer root URL without credentials.',
      );
    }
    if (fileIndex != null && fileIndex < 0) {
      throw RangeError.value(fileIndex, 'fileIndex', 'Must be zero or greater.');
    }

    final source = MediaStreamSource(
      id: 'torrent-source',
      label: 'User-provided torrent',
      uri: magnetUri,
    );
    if (!source.isMagnet) {
      throw ArgumentError.value(
        magnetUri,
        'magnetUri',
        'Must contain a valid BitTorrent info hash.',
      );
    }

    return config.baseUri.replace(
      path: '/stream',
      queryParameters: <String, String>{
        'link': magnetUri.toString(),
        if (fileIndex != null) 'index': fileIndex.toString(),
        'play': play.toString(),
      },
    );
  }
}
