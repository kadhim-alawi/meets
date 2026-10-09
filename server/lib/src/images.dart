import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Same-origin image proxy. Flutter web (CanvasKit) can only draw images
/// whose host sends CORS headers, and Qloo image hosts do not, so the app
/// asks the server instead. Only URLs that arrived inside Qloo responses are
/// served, which keeps the proxy from being an open relay.
class ImageProxy {
  ImageProxy({http.Client? client, this.maxBytes = 6 * 1024 * 1024, this.maxCacheBytes = 80 * 1024 * 1024})
      : _http = client ?? http.Client();

  final http.Client _http;
  final int maxBytes;
  final int maxCacheBytes;
  final Set<String> _allowed = {};
  final _cache = <String, (String, Uint8List)>{};
  int _cacheBytes = 0;

  void allow(String? url) {
    if (url == null) return;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return;
    if (_allowed.length > 50000) _allowed.remove(_allowed.first);
    _allowed.add(url);
  }

  void allowAll(Iterable<String?> urls) => urls.forEach(allow);

  bool isAllowed(String url) => _allowed.contains(url);

  /// Returns (contentType, bytes) or null when the URL is not allowed or the
  /// upstream does not return an image.
  Future<(String, Uint8List)?> fetch(String url) async {
    if (!_allowed.contains(url)) return null;
    final hit = _cache[url];
    if (hit != null) return hit;
    try {
      final res = await _get(Uri.parse(url));
      if (res == null) return null;
      final type = res.headers['content-type'] ?? '';
      if (res.statusCode != 200 || !type.startsWith('image/') || res.bodyBytes.length > maxBytes) return null;
      final entry = (type, res.bodyBytes);
      _cache[url] = entry;
      _cacheBytes += res.bodyBytes.length;
      while (_cacheBytes > maxCacheBytes && _cache.isNotEmpty) {
        final first = _cache.keys.first;
        _cacheBytes -= _cache.remove(first)!.$2.length;
      }
      return entry;
    } on Object {
      return null;
    }
  }

  static bool _publicHttps(Uri uri) {
    final host = uri.host.toLowerCase();
    if (uri.scheme != 'https' || host.isEmpty) return false;
    if (host == 'localhost' || host.endsWith('.local') || host.endsWith('.internal')) return false;
    // Reject IP literals; image hosts are always named.
    if (RegExp(r'^[\d.]+$').hasMatch(host) || host.contains(':')) return false;
    return true;
  }

  /// GET that follows at most three redirects, each to a public https host.
  Future<http.Response?> _get(Uri uri) async {
    var current = uri;
    for (var hop = 0; hop < 4; hop++) {
      if (!_publicHttps(current)) return null;
      final request = http.Request('GET', current)..followRedirects = false;
      final streamed = await _http.send(request).timeout(const Duration(seconds: 12));
      final res = await http.Response.fromStream(streamed).timeout(const Duration(seconds: 12));
      if (res.isRedirect || (res.statusCode >= 300 && res.statusCode < 400)) {
        final location = res.headers['location'];
        if (location == null) return null;
        current = current.resolve(location);
        continue;
      }
      return res;
    }
    return null;
  }
}
