import 'dart:convert';
import 'dart:io';

import 'package:meets_core/meets_core.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'agent/emitter.dart';
import 'agent/qloo_service.dart';
import 'config.dart';
import 'export.dart';
import 'images.dart';
import 'mcp.dart';
import 'net.dart';
import 'qloo/qloo_client.dart';
import 'runs.dart';

Response jsonResponse(Object body, {int status = 200, Map<String, String> headers = const {}}) =>
    Response(status, body: jsonEncode(body), headers: {'content-type': 'application/json; charset=utf-8', ...headers});

Response problem(int status, String message) => jsonResponse({'error': message}, status: status);


/// One example brief shown on the home page.
class Example {
  const Example({required this.id, required this.title, required this.blurb, required this.brief, this.kitId});

  final String id;
  final String title;
  final String blurb;
  final Brief brief;
  final String? kitId;

  Json toJson() => compact({'id': id, 'title': title, 'blurb': blurb, 'brief': brief.toJson(), 'kitId': kitId});
}

Future<List<Example>> loadExamples(String dir) async {
  final file = File(p.join(dir, 'examples.json'));
  if (!await file.exists()) return const [];
  final json = asList(jsonDecode(await file.readAsString()));
  return json
      .map(asJson)
      .map((e) => Example(
            id: asString(e['id']) ?? '',
            title: asString(e['title']) ?? '',
            blurb: asString(e['blurb']) ?? '',
            brief: Brief.fromJson(asJson(e['brief'])),
            kitId: asString(e['kitId']),
          ))
      .toList();
}

class Api {
  Api({
    required this.config,
    required this.client,
    required this.runs,
    required this.kits,
    required this.images,
    required this.examples,
  });

  final Config config;
  final QlooClient? client;
  final RunManager? runs;
  final KitStore kits;
  final ImageProxy images;
  final List<Example> examples;
  final _searchHits = <String, List<DateTime>>{};

  bool get _qlooReady => client != null && runs != null;

  Router get router {
    final r = Router();
    r.get('/api/health', _health);
    r.get('/api/examples', _examples);
    r.get('/api/search', _search);
    r.post('/api/runs', _startRun);
    r.get('/api/runs/<id>', _getRun);
    r.get('/api/kits/<id>', _getKit);
    r.post('/api/kits/<id>/refine', _refine);
    r.post('/api/kits/<id>/gutcheck', _gutCheck);
    r.get('/api/kits/<id>/export.md', _exportMd);
    r.get('/api/kits/<id>/export.csv', _exportCsv);
    r.get('/api/img', _image);
    if (_qlooReady) {
      final mcp = McpEndpoint(runs: runs!, publicUrl: config.publicUrl);
      r.all('/mcp', mcp.handle);
    }
    r.all('/api/<rest|.*>', (Request _) => problem(404, 'Not found'));
    return r;
  }

  Response _health(Request request) => jsonResponse({
        'ok': true,
        'qloo': config.qlooMode,
        'llm': config.llmEnabled,
        'model': config.llmEnabled ? config.llmModel : null,
        'monthRemaining': client?.monthRemaining,
        'mcp': _qlooReady,
      });

  Response _examples(Request request) => jsonResponse({
        'examples': examples.map((e) {
          final baked = e.kitId != null && kits.contains(e.kitId!);
          return Example(id: e.id, title: e.title, blurb: e.blurb, brief: e.brief, kitId: baked ? e.kitId : null).toJson();
        }).toList(),
      });

  Future<Response> _search(Request request) async {
    final c = client;
    if (c == null) return problem(503, 'Qloo is not configured on this server.');
    final q = (request.url.queryParameters['q'] ?? '').trim();
    if (q.length < 2) return jsonResponse({'results': []});
    if (q.length > 80) return problem(400, 'Query too long.');
    final ip = clientIp(request);
    final now = DateTime.now();
    if (_searchHits.length > 5000) {
      _searchHits.removeWhere((_, list) => list.every((t) => now.difference(t) > const Duration(minutes: 1)));
    }
    final hits = _searchHits.putIfAbsent(ip, () => [])..removeWhere((t) => now.difference(t) > const Duration(minutes: 1));
    if (hits.length >= 90) return problem(429, 'Slow down a little.');
    hits.add(now);
    final kinds = (request.url.queryParameters['kinds'] ?? '')
        .split(',')
        .map(EntityKind.fromName)
        .where((k) => k != EntityKind.unknown)
        .toList();
    try {
      final service = QlooService(c, ListEmitter());
      final results = await service.search(q, kinds: kinds, take: 8);
      images.allowAll(results.map((e) => e.imageUrl));
      return jsonResponse({'results': results.map((e) => e.toJson()).toList()});
    } on QlooException catch (e) {
      return problem(502, 'Qloo search failed: ${e.message}');
    }
  }

  Future<Response> _startRun(Request request) async {
    final manager = runs;
    if (manager == null) return problem(503, 'Qloo is not configured on this server, so new kits cannot be built. Example kits still work.');
    try {
      final body = asJson(jsonDecode(await request.readAsString()));
      final brief = Brief.fromJson(asJson(body['brief']));
      final record = manager.startBuild(brief, clientIp(request));
      return jsonResponse({'runId': record.id, 'kitId': record.kitId}, status: 202);
    } on FormatException {
      return problem(400, 'Body must be JSON.');
    } on ArgumentError catch (e) {
      return problem(400, '${e.message}');
    } on LimitExceeded catch (e) {
      return problem(429, e.message);
    }
  }

  Response _getRun(Request request, String id) {
    final record = runs?.run(id);
    if (record == null) return problem(404, 'This run has expired. Open the kit link instead.');
    final after = int.tryParse(request.url.queryParameters['after'] ?? '') ?? 0;
    return jsonResponse(record.snapshot(after: after).toJson());
  }

  Response _getKit(Request request, String id) {
    final kit = kits.get(id);
    if (kit == null) return problem(404, 'No kit with that id.');
    return jsonResponse({'kit': kit.toJson(), 'trace': kits.traceOf(id).map((e) => e.toJson()).toList()});
  }

  Future<Response> _refine(Request request, String id) async {
    final manager = runs;
    if (manager == null) return problem(503, 'Qloo is not configured on this server.');
    try {
      final body = asJson(jsonDecode(await request.readAsString()));
      final record = manager.startRefine(id, asString(body['message']) ?? '', clientIp(request));
      return jsonResponse({'runId': record.id, 'kitId': id}, status: 202);
    } on FormatException {
      return problem(400, 'Body must be JSON.');
    } on StateError {
      return problem(404, 'No kit with that id.');
    } on ArgumentError catch (e) {
      return problem(400, '${e.message}');
    } on LimitExceeded catch (e) {
      return problem(429, e.message);
    }
  }

  Future<Response> _gutCheck(Request request, String id) async {
    final manager = runs;
    if (manager == null) return problem(503, 'Qloo is not configured on this server.');
    try {
      final record = manager.startGutCheck(id, clientIp(request));
      return jsonResponse({'runId': record.id, 'kitId': id}, status: 202);
    } on StateError {
      return problem(404, 'No kit with that id.');
    } on ArgumentError catch (e) {
      return problem(400, '${e.message}');
    } on LimitExceeded catch (e) {
      return problem(429, e.message);
    }
  }

  String _slug(CompKit kit) {
    final base = kit.brief.title.isEmpty ? 'comp-kit' : kit.brief.title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    return base.replaceAll(RegExp(r'^-+|-+$'), '');
  }

  Response _exportMd(Request request, String id) {
    final kit = kits.get(id);
    if (kit == null) return problem(404, 'No kit with that id.');
    final url = config.publicUrl.isEmpty ? null : '${config.publicUrl}/kit/$id';
    return Response.ok(kitMarkdown(kit, url: url), headers: {
      'content-type': 'text/markdown; charset=utf-8',
      'content-disposition': 'attachment; filename="${_slug(kit)}-comp-kit.md"',
    });
  }

  Response _exportCsv(Request request, String id) {
    final kit = kits.get(id);
    if (kit == null) return problem(404, 'No kit with that id.');
    return Response.ok(kitCsv(kit), headers: {
      'content-type': 'text/csv; charset=utf-8',
      'content-disposition': 'attachment; filename="${_slug(kit)}-comps.csv"',
    });
  }

  Future<Response> _image(Request request) async {
    final url = request.url.queryParameters['u'];
    if (url == null) return Response.notFound('');
    final hit = await images.fetch(url);
    if (hit == null) return Response.notFound('');
    return Response.ok(hit.$2, headers: {'content-type': hit.$1, 'cache-control': 'public, max-age=604800, immutable'});
  }
}

/// Permissive CORS for the JSON API (no cookies are used), so a Flutter
/// dev server or a mobile build can talk to a deployed backend.
Middleware cors() => (inner) => (request) async {
      const headers = {
        'access-control-allow-origin': '*',
        'access-control-allow-methods': 'GET, POST, OPTIONS',
        'access-control-allow-headers': 'content-type, mcp-protocol-version, mcp-session-id',
      };
      if (request.method == 'OPTIONS') return Response.ok('', headers: headers);
      final response = await inner(request);
      return response.change(headers: headers);
    };

/// Serves the Flutter web build with an SPA fallback to index.html.
Handler staticSite(String webDir) {
  final root = Directory(webDir).absolute.path;
  const types = {
    '.html': 'text/html; charset=utf-8',
    '.js': 'application/javascript',
    '.mjs': 'application/javascript',
    '.json': 'application/json',
    '.css': 'text/css',
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.svg': 'image/svg+xml',
    '.ico': 'image/x-icon',
    '.wasm': 'application/wasm',
    '.ttf': 'font/ttf',
    '.otf': 'font/otf',
    '.woff2': 'font/woff2',
    '.bin': 'application/octet-stream',
    '.frag': 'application/octet-stream',
    '.txt': 'text/plain; charset=utf-8',
    '.webmanifest': 'application/manifest+json',
  };
  return (Request request) async {
    if (request.method != 'GET' && request.method != 'HEAD') return Response.notFound('');
    final rel = p.normalize(Uri.decodeComponent(request.url.path));
    if (rel.startsWith('..') || p.isAbsolute(rel)) return Response.forbidden('');
    var file = File(p.join(root, rel.isEmpty || rel == '.' ? 'index.html' : rel));
    if (!await file.exists()) {
      // Deep links like /kit/abc are app routes.
      if (p.extension(rel).isNotEmpty) return Response.notFound('Not found');
      file = File(p.join(root, 'index.html'));
      if (!await file.exists()) {
        return Response.ok('Meets API is running. Build the Flutter app (app/) to serve the web UI here.',
            headers: {'content-type': 'text/plain'});
      }
    }
    final name = p.basename(file.path);
    final cache = name == 'index.html' || name == 'flutter_service_worker.js' || name == 'version.json' || name == 'flutter_bootstrap.js'
        ? 'no-cache'
        : 'public, max-age=3600';
    return Response.ok(request.method == 'HEAD' ? null : file.openRead(), headers: {
      'content-type': types[p.extension(file.path)] ?? 'application/octet-stream',
      'cache-control': cache,
    });
  };
}
