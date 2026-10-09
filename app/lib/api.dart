import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:meets_core/meets_core.dart';

/// What the server can do right now.
class Health {
  const Health({required this.qloo, required this.llm, this.model, this.mcp = false});

  /// `live`, `preview` or `off`.
  final String qloo;
  final bool llm;
  final String? model;
  final bool mcp;

  bool get canBuild => qloo != 'off';

  static const unknown = Health(qloo: 'live', llm: true);
}

class Example {
  const Example({required this.id, required this.title, required this.blurb, required this.brief, this.kitId});

  final String id;
  final String title;
  final String blurb;
  final Brief brief;
  final String? kitId;

  factory Example.fromJson(Json json) => Example(
        id: asString(json['id']) ?? '',
        title: asString(json['title']) ?? '',
        blurb: asString(json['blurb']) ?? '',
        brief: Brief.fromJson(asJson(json['brief'])),
        kitId: asString(json['kitId']),
      );
}

class ApiError implements Exception {
  ApiError(this.message, [this.status]);

  final String message;
  final int? status;

  @override
  String toString() => message;
}

/// Talks to the Meets server. On the web it defaults to the page's origin;
/// mobile builds pass `--dart-define=API_BASE=https://your-host`.
class Api {
  Api._(this.base);

  static final Api instance = Api._(_resolveBase());

  static String _resolveBase() {
    const configured = String.fromEnvironment('API_BASE');
    if (configured.isNotEmpty) return configured.endsWith('/') ? configured.substring(0, configured.length - 1) : configured;
    final origin = Uri.base;
    if (origin.scheme == 'http' || origin.scheme == 'https') return origin.origin;
    return 'http://localhost:8080';
  }

  final String base;
  final http.Client _http = http.Client();
  Health? _health;

  Uri _u(String path, [Map<String, String>? query]) => Uri.parse('$base$path').replace(queryParameters: query);

  Future<Json> _get(String path, [Map<String, String>? query]) async {
    final res = await _http.get(_u(path, query)).timeout(const Duration(seconds: 30));
    return _decode(res);
  }

  Future<Json> _post(String path, Json body) async {
    final res = await _http
        .post(_u(path), headers: {'content-type': 'application/json'}, body: jsonEncode(body))
        .timeout(const Duration(seconds: 30));
    return _decode(res);
  }

  Json _decode(http.Response res) {
    Json body;
    try {
      body = asJson(jsonDecode(utf8.decode(res.bodyBytes)));
    } on FormatException {
      body = const {};
    }
    if (res.statusCode >= 400) {
      throw ApiError(asString(body['error']) ?? 'The server answered ${res.statusCode}.', res.statusCode);
    }
    return body;
  }

  Future<Health> health() async {
    final cached = _health;
    if (cached != null) return cached;
    try {
      final json = await _get('/api/health');
      return _health = Health(
        qloo: asString(json['qloo']) ?? 'off',
        llm: asBool(json['llm']),
        model: asString(json['model']),
        mcp: asBool(json['mcp']),
      );
    } on Object {
      return Health.unknown;
    }
  }

  Future<List<Example>> examples() async {
    final json = await _get('/api/examples');
    return listOf(json['examples'], Example.fromJson);
  }

  Future<List<Entity>> search(String query, List<EntityKind> kinds) async {
    final json = await _get('/api/search', {'q': query, 'kinds': kinds.map((k) => k.name).join(',')});
    return listOf(json['results'], Entity.fromJson);
  }

  /// Returns (runId, kitId).
  Future<(String, String)> startRun(Brief brief) async {
    final json = await _post('/api/runs', {'brief': brief.toJson()});
    return (asString(json['runId'])!, asString(json['kitId'])!);
  }

  Future<RunSnapshot> run(String id, {int after = 0}) async => RunSnapshot.fromJson(await _get('/api/runs/$id', {'after': '$after'}));

  Future<(CompKit, List<RunEvent>)> kit(String id) async {
    final json = await _get('/api/kits/$id');
    return (CompKit.fromJson(asJson(json['kit'])), listOf(json['trace'], RunEvent.fromJson));
  }

  Future<String> refine(String kitId, String message) async =>
      asString((await _post('/api/kits/$kitId/refine', {'message': message}))['runId'])!;

  Future<String> gutCheck(String kitId) async => asString((await _post('/api/kits/$kitId/gutcheck', const {}))['runId'])!;

  /// Polls a run until it finishes, yielding each new snapshot.
  Stream<RunSnapshot> follow(String runId, {Duration every = const Duration(milliseconds: 650)}) async* {
    var after = 0;
    var failures = 0;
    while (true) {
      RunSnapshot snap;
      try {
        snap = await run(runId, after: after);
        failures = 0;
      } on ApiError {
        rethrow;
      } on Object {
        if (++failures > 6) throw ApiError('Lost contact with the server.');
        await Future<void>.delayed(every * 2);
        continue;
      }
      if (snap.events.isNotEmpty) after = snap.events.last.seq;
      yield snap;
      if (snap.status.finished) return;
      await Future<void>.delayed(every);
    }
  }

  String exportUrl(String kitId, String ext) => '$base/api/kits/$kitId/export.$ext';

  String? imageUrl(String? url) => url == null ? null : '$base/api/img?u=${Uri.encodeQueryComponent(url)}';

  String kitLink(String kitId) {
    final origin = Uri.base;
    final host = (origin.scheme == 'http' || origin.scheme == 'https') ? origin.origin : base;
    return '$host/kit/$kitId';
  }
}
