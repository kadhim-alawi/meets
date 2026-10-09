import 'dart:io';

import 'package:meets_server/meets_server.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;

Future<void> main() async {
  final config = Config.fromEnvironment();
  final images = ImageProxy();
  final kits = KitStore(dataDir: config.dataDir, examplesDir: config.examplesDir, images: images);
  await kits.load();

  QlooClient? client;
  switch (config.qlooMode) {
    case 'live':
      client = QlooClient(
        apiKey: config.qlooKey,
        baseUrl: config.qlooBaseUrl,
        minInterval: Duration(milliseconds: config.qlooMinIntervalMs),
        cacheDir: p.join(config.dataDir, 'qloo-cache'),
      );
    case 'preview':
      stdout.writeln('QLOO_MODE=preview: serving labelled SAMPLE data, not Qloo. Never use this for a public demo.');
      client = QlooClient(apiKey: 'preview', mode: 'preview', transport: previewTransport, minInterval: Duration.zero);
    default:
      stdout.writeln('No QLOO_API_KEY: new kits are disabled; saved and example kits still load.');
  }

  final llm = config.llmEnabled
      ? LlmClient(apiKey: config.anthropicKey, model: config.llmModel, effort: config.llmEffort, baseUrl: config.anthropicBaseUrl)
      : null;

  final runs = client == null
      ? null
      : RunManager(
          client: client,
          llm: llm,
          kits: kits,
          images: images,
          runsPerHourPerIp: config.runsPerHourPerIp,
          runsPerDay: config.runsPerDay,
          maxConcurrent: config.maxConcurrentRuns,
        );

  final api = Api(
    config: config,
    client: client,
    runs: runs,
    kits: kits,
    images: images,
    examples: await loadExamples(config.examplesDir),
  );

  final handler = const Pipeline()
      .addMiddleware(_log())
      .addMiddleware(cors())
      .addHandler(Cascade().add(api.router.call).add(staticSite(config.webDir)).handler);

  final server = await io.serve(handler, config.host, config.port);
  server.autoCompress = true;
  stdout.writeln('Meets listening on http://${server.address.host}:${server.port} '
      '(qloo: ${config.qlooMode}, llm: ${llm == null ? 'off' : llm.model})');
}

Middleware _log() => (inner) => (request) async {
      final started = DateTime.now();
      final response = await inner(request);
      final path = request.url.path;
      if (path.startsWith('api/') || path == 'mcp') {
        stdout.writeln('${response.statusCode} ${request.method} /$path ${DateTime.now().difference(started).inMilliseconds}ms');
      }
      return response;
    };
