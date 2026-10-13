abstract final class MediaHeaders {
  static const _desktopChromeUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/122.0.0.0 Safari/537.36';

  static Map<String, String> getHeaders(String url) {
    final uri = Uri.tryParse(url);
    final hasValidHost = uri != null && uri.hasAuthority && uri.host.isNotEmpty;

    return {
      'User-Agent': _desktopChromeUserAgent,
      'Accept': '*/*',
      if (hasValidHost) 'Referer': '${uri!.scheme}://${uri.host}/',
    };
  }
}
