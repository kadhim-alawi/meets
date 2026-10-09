// Pre-builds the example kits so visitors (and judges) get instant results
// without spending the shared Qloo quota. Uses the real API and, if set, the
// language model:
//
//   QLOO_API_KEY=... ANTHROPIC_API_KEY=... dart run bin/bake.dart [--only=id] [--force]
//
// Kits are written to examples/kits/<kitId>.json and ship with the image.
import 'dart:convert';
import 'dart:io';

import 'package:meets_server/meets_server.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  final config = Config.fromEnvironment();
  if (config.qlooMode != 'live') {
    stderr.writeln('Baking needs live Qloo data: set QLOO_API_KEY (preview data must never be baked).');
    exit(2);
  }
  final only = args.where((a) => a.startsWith('--only=')).map((a) => a.substring(7)).toSet();
  final force = args.contains('--force');
  final client = QlooClient(apiKey: config.qlooKey, baseUrl: config.qlooBaseUrl, cacheDir: p.join(config.dataDir, 'qloo-cache'));
  final llm = config.llmEnabled
      ? LlmClient(apiKey: config.anthropicKey, model: config.llmModel, effort: config.llmEffort, baseUrl: config.anthropicBaseUrl)
      : null;
  final agent = CompsAgent(client: client, llm: llm);
  final examples = await loadExamples(config.examplesDir);
  final outDir = Directory(p.join(config.examplesDir, 'kits'))..createSync(recursive: true);

  for (final ex in examples) {
    final kitId = ex.kitId;
    if (kitId == null || (only.isNotEmpty && !only.contains(ex.id))) continue;
    final file = File(p.join(outDir.path, '$kitId.json'));
    if (file.existsSync() && !force) {
      stdout.writeln('skip  ${ex.id} (exists; --force to rebuild)');
      continue;
    }
    stdout.writeln('bake  ${ex.id} …');
    final emitter = ListEmitter(onEvent: (e) => stdout.writeln('      ${e.kind.padRight(8)} ${e.title}'));
    try {
      final kit = await agent.build(ex.brief, emitter, kitId: kitId);
      file.writeAsStringSync(jsonEncode({'kit': kit.toJson(), 'trace': emitter.events.map((e) => e.toJson()).toList()}));
      stdout.writeln('done  ${ex.id}: ${kit.pairing?.line ?? '(no pairing)'} · ${kit.stats.qlooCalls} calls');
    } on Object catch (e) {
      stderr.writeln('FAIL  ${ex.id}: $e');
    }
  }
  client.close();
  llm?.close();
}
