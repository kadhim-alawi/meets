import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:meets_core/meets_core.dart';
import 'package:path/path.dart' as p;

/// Raw HTTP result handed back by a [QlooTransport].
class QlooHttpResponse {
  const QlooHttpResponse(this.status, this.body, [this.headers = const {}]);

  final int status;
  final String body;
  final Map<String, String> headers;
}

/// Sends one GET. Swappable so tests and preview mode never touch the network.
typedef QlooTransport = Future<QlooHttpResponse> Function(Uri uri, Map<String, String> headers);

/// One Qloo request as recorded for the audit trail.
class QlooCall {
  QlooCall({required this.path, required this.params, required this.status, required this.ms, required this.cached, this.error});

  final String path;
  final Map<String, String> params;
  final int status;
  final int ms;
  final bool cached;
  final String? error;
}

class QlooException implements Exception {
  QlooException(this.path, this.status, this.message);

  final String path;
  final int? status;
  final String message;

  @override
  String toString() => 'Qloo $path failed${status == null ? '' : ' ($status)'}: $message';
}

/// Thin, careful client for the Qloo hackathon API.
///
/// * Sends `X-Api-Key` to the hackathon host (hackathon keys 401 elsewhere).
/// * Spaces request starts so a shared key stays under its per-second limit.
/// * Shares identical in-flight requests and caches successful responses in
///   memory and, when [cacheDir] is set, on disk.
/// * Rejects parameter names Qloo does not document, because the API ignores
///   unknown names silently and returns unfiltered results.
class QlooClient {
  QlooClient({
    required String apiKey,
    String baseUrl = 'https://hackathon.api.qloo.com',
    QlooTransport? transport,
    this.mode = 'live',
    Duration minInterval = const Duration(milliseconds: 260),
    this.maxRetries = 2,
    this.cacheTtl = const Duration(days: 3),
    this.cacheDir,
    this.maxMemoryEntries = 4000,
    // A heavy insights request Qloo hasn't seen can take over a minute the
    // first time (71s measured) and ~10s after; a shorter limit never lets it finish.
    Duration timeout = const Duration(seconds: 90),
  })  : _apiKey = apiKey,
        _base = Uri.parse(baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl),
        _minInterval = minInterval,
        _timeout = timeout {
    _transport = transport ?? _httpTransport;
  }

  final String _apiKey;
  final Uri _base;
  final Duration _minInterval;
  final Duration _timeout;
  late final QlooTransport _transport;
  final http.Client _http = http.Client();

  /// `live` or `preview`. Preview transports serve labelled sample data.
  final String mode;
  final int maxRetries;
  final Duration cacheTtl;
  final String? cacheDir;
  final int maxMemoryEntries;

  DateTime _nextSlot = DateTime.fromMillisecondsSinceEpoch(0);
  final _inFlight = <String, Future<Json>>{};
  final _memory = <String, (DateTime, Json)>{};

  /// Remaining monthly quota when Qloo reports it.
  int? monthRemaining;
  int totalCalls = 0;
  int cachedCalls = 0;

  /// Which spelling of the video game type this host accepts.
  String videoGameUrn = EntityKind.videoGame.urn;

  static const _exactParams = {
    'take',
    'page',
    'offset',
    'sort_by',
    'query',
    'types',
    'entity_ids',
    'a.signal.interests.entities',
    'b.signal.interests.entities',
  };
  static const _paramPrefixes = ['filter.', 'signal.', 'bias.', 'diversify.', 'feature.', 'operator.', 'output.'];

  static void checkParam(String name) {
    if (_exactParams.contains(name) || _paramPrefixes.any(name.startsWith)) return;
    throw ArgumentError.value(name, 'param', 'not a documented Qloo parameter (it would be ignored silently)');
  }

  static String encodeValue(Object value) {
    if (value is bool) return value ? 'true' : 'false';
    if (value is Iterable) return value.map((v) => encodeValue(v as Object)).join(',');
    if (value is double) return value.toStringAsFixed(4).replaceFirst(RegExp(r'\.?0+$'), '');
    return value.toString();
  }

  /// Normalises params: drops empties, validates names, sorts keys.
  static Map<String, String> cleanParams(Map<String, Object?> params) {
    final out = <String, String>{};
    final keys = params.keys.toList()..sort();
    for (final key in keys) {
      final value = params[key];
      if (value == null) continue;
      if (value is String && value.isEmpty) continue;
      if (value is Iterable && value.isEmpty) continue;
      checkParam(key);
      out[key] = encodeValue(value);
    }
    return out;
  }

  /// GET [path] with [params]. [onCall] receives an audit record.
  Future<Json> get(String path, Map<String, Object?> params,
      {void Function(QlooCall call)? onCall, bool retriedGameType = false}) async {
    final clean = cleanParams(params);
    // The hackathon guide and the Insights reference spell the game type
    // differently; use whichever this host accepted last.
    if (clean['filter.type'] == EntityKind.videoGame.urn || clean['filter.type'] == EntityKind.videoGameAlias) {
      clean['filter.type'] = videoGameUrn;
    }
    final key = '$path?${Uri(queryParameters: clean).query}';
    final started = DateTime.now();

    final cached = await _readCache(key);
    if (cached != null) {
      totalCalls++;
      cachedCalls++;
      onCall?.call(QlooCall(path: path, params: clean, status: 200, ms: 0, cached: true));
      return cached;
    }

    final pending = _inFlight[key];
    if (pending != null) {
      final json = await pending;
      onCall?.call(QlooCall(path: path, params: clean, status: 200, ms: DateTime.now().difference(started).inMilliseconds, cached: true));
      return json;
    }

    final future = _fetch(path, clean, key);
    _inFlight[key] = future;
    try {
      final json = await future;
      totalCalls++;
      onCall?.call(QlooCall(path: path, params: clean, status: 200, ms: DateTime.now().difference(started).inMilliseconds, cached: false));
      return json;
    } on QlooException catch (e) {
      // Retry once with the other spelling of the game type.
      final type = clean['filter.type'];
      if (!retriedGameType && e.status == 400 && (type == EntityKind.videoGame.urn || type == EntityKind.videoGameAlias)) {
        videoGameUrn = type == EntityKind.videoGame.urn ? EntityKind.videoGameAlias : EntityKind.videoGame.urn;
        return get(path, {...clean, 'filter.type': videoGameUrn}, onCall: onCall, retriedGameType: true);
      }
      totalCalls++;
      onCall?.call(QlooCall(
          path: path,
          params: clean,
          status: e.status ?? 0,
          ms: DateTime.now().difference(started).inMilliseconds,
          cached: false,
          error: e.message));
      rethrow;
    } finally {
      _inFlight.remove(key);
    }
  }

  Future<Json> _fetch(String path, Map<String, String> params, String key) async {
    final uri = _base.replace(path: '${_base.path}$path', queryParameters: params.isEmpty ? null : params);
    final headers = {'X-Api-Key': _apiKey, 'Accept': 'application/json'};
    for (var attempt = 0;; attempt++) {
      await _throttle();
      QlooHttpResponse res;
      try {
        res = await _transport(uri, headers).timeout(_timeout);
      } on TimeoutException {
        if (attempt < 1) continue;
        throw QlooException(path, null, 'timed out after ${_timeout.inSeconds}s');
      } on SocketException catch (e) {
        if (attempt < 1) continue;
        throw QlooException(path, null, 'network error: ${e.message}');
      } on http.ClientException catch (e) {
        if (attempt < 1) continue;
        throw QlooException(path, null, 'network error: ${e.message}');
      }
      final remaining = int.tryParse(res.headers['x-month-ratelimit-remaining'] ?? '');
      if (remaining != null) monthRemaining = remaining;
      if (res.status >= 200 && res.status < 300) {
        final Object? decoded;
        try {
          decoded = jsonDecode(res.body);
        } on FormatException {
          throw QlooException(path, res.status, 'response was not JSON');
        }
        final json = asJson(decoded);
        await _writeCache(key, json);
        return json;
      }
      final retryable = res.status == 429 || res.status >= 500;
      if (retryable && attempt < maxRetries) {
        final reset = double.tryParse(res.headers['x-second-ratelimit-reset'] ?? res.headers['retry-after'] ?? '');
        final wait = reset != null ? Duration(milliseconds: (reset * 1000).clamp(250, 5000).round()) : Duration(milliseconds: 600 * (attempt + 1));
        await Future<void>.delayed(wait);
        continue;
      }
      throw QlooException(path, res.status, _errorMessage(res.body));
    }
  }

  static String _errorMessage(String body) {
    try {
      final json = asJson(jsonDecode(body));
      final error = json['error'];
      final message = asString(error is Map ? error['message'] : error) ?? asString(json['message']);
      if (message != null) return message.length > 240 ? '${message.substring(0, 240)}…' : message;
    } on FormatException {
      // fall through
    }
    final text = body.trim();
    return text.isEmpty ? 'empty response' : (text.length > 240 ? '${text.substring(0, 240)}…' : text);
  }

  Future<void> _throttle() async {
    final now = DateTime.now();
    final slot = _nextSlot.isAfter(now) ? _nextSlot : now;
    _nextSlot = slot.add(_minInterval);
    final wait = slot.difference(now);
    if (wait > Duration.zero) await Future<void>.delayed(wait);
  }

  Future<QlooHttpResponse> _httpTransport(Uri uri, Map<String, String> headers) async {
    final res = await _http.get(uri, headers: headers);
    return QlooHttpResponse(res.statusCode, utf8.decode(res.bodyBytes, allowMalformed: true), res.headers);
  }

  // -- cache ---------------------------------------------------------------

  String _hash(String key) => sha1.convert(utf8.encode('$mode|$key')).toString();

  Future<Json?> _readCache(String key) async {
    final hit = _memory[key];
    if (hit != null) {
      if (DateTime.now().isBefore(hit.$1)) {
        // Refresh LRU order.
        _memory.remove(key);
        _memory[key] = hit;
        return hit.$2;
      }
      _memory.remove(key);
    }
    final dir = cacheDir;
    if (dir == null) return null;
    final file = File(p.join(dir, '${_hash(key)}.json'));
    try {
      if (!await file.exists()) return null;
      final stat = await file.stat();
      if (DateTime.now().difference(stat.modified) > cacheTtl) return null;
      final json = asJson(jsonDecode(await file.readAsString()));
      _remember(key, json);
      return json;
    } on Object {
      return null;
    }
  }

  Future<void> _writeCache(String key, Json json) async {
    _remember(key, json);
    final dir = cacheDir;
    if (dir == null) return;
    try {
      final file = File(p.join(dir, '${_hash(key)}.json'));
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(json));
    } on Object {
      // Disk cache is best effort.
    }
  }

  void _remember(String key, Json json) {
    _memory[key] = (DateTime.now().add(cacheTtl), json);
    while (_memory.length > maxMemoryEntries) {
      _memory.remove(_memory.keys.first);
    }
  }

  void close() => _http.close();
}
