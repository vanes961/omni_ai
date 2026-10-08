import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class NetworkImageWithFallback extends StatelessWidget {
  const NetworkImageWithFallback({
    required this.url,
    required this.errorBuilder,
    this.fallbackUrls = const [],
    this.headers,
    this.fit,
    super.key,
  });

  final String url;
  final List<String> fallbackUrls;
  final Map<String, String>? headers;
  final BoxFit? fit;
  final ImageErrorWidgetBuilder errorBuilder;

  @override
  Widget build(BuildContext context) {
    final urls = [url, ...fallbackUrls]
        .map((candidate) => candidate.trim())
        .where((candidate) => candidate.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (urls.isEmpty) {
      return errorBuilder(
        context,
        ArgumentError.value(url, 'url', 'No image URLs were provided.'),
        StackTrace.current,
      );
    }
    return _buildImage(context, urls, 0);
  }

  Widget _buildImage(BuildContext context, List<String> urls, int index) {
    return CachedNetworkImage(
      imageUrl: urls[index],
      httpHeaders: headers,
      fit: fit,
      progressIndicatorBuilder: (context, url, progress) =>
          const SizedBox.shrink(),
      errorWidget: (context, url, error) {
        if (index + 1 < urls.length) {
          return _buildImage(context, urls, index + 1);
        }
        return errorBuilder(context, error, StackTrace.current);
      },
    );
  }
}
