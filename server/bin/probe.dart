// Live contract check: calls every Qloo request shape Meets depends on and
// reports what came back. Run once when the hackathon key arrives:
//
//   QLOO_API_KEY=... dart run bin/probe.dart
//
// Trimmed raw responses are written to data/probe/ for debugging.
import 'dart:convert';
import 'dart:io';

import 'package:meets_core/meets_core.dart';
import 'package:meets_server/meets_server.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  final config = Config.fromEnvironment();
  if (config.qlooKey.isEmpty) {
    stderr.writeln('Set QLOO_API_KEY first.');
    exit(2);
  }
  final client = QlooClient(apiKey: config.qlooKey, baseUrl: config.qlooBaseUrl);
  final outDir = Directory(p.join(config.dataDir, 'probe'))..createSync(recursive: true);
  var failures = 0;
  final rows = <String>[];

  Future<Json?> check(String name, String path, Map<String, Object?> params, String Function(Json) describe,
      {bool critical = true}) async {
    final started = DateTime.now();
    try {
      final json = await client.get(path, params);
      final ms = DateTime.now().difference(started).inMilliseconds;
      File(p.join(outDir.path, '${name.replaceAll(RegExp(r'[^a-z0-9]+'), '_')}.json'))
          .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(_trim(json)));
      final summary = describe(json);
      rows.add('PASS  $name  (${ms}ms)  $summary');
      return json;
    } on QlooException catch (e) {
      if (critical) failures++;
      rows.add('${critical ? 'FAIL' : 'WARN'}  $name  HTTP ${e.status}: ${e.message}');
      return null;
    }
  }

  String entities(Json j) {
    final list = parseInsightsEntities(j);
    if (list.isEmpty) return '0 entities';
    final e = list.first;
    return '${list.length} entities; first: "${e.name}" kind=${e.kind.name} year=${e.year} creator=${e.creator} '
        'pop=${e.popularity?.toStringAsFixed(5)} aff=${e.affinity?.toStringAsFixed(3)} drivers=${e.drivers.length} '
        'tags=${e.tags.take(3).map((t) => t.name).join('/')} image=${e.imageUrl != null}';
  }

  final search = await check('search book', '/search', {'query': 'Piranesi', 'types': ['urn:entity:book'], 'take': 5}, (j) {
    final list = parseSearch(j);
    final e = list.isEmpty ? null : list.first;
    return '${list.length} results; first "${e?.name}" kind=${e?.kind.name} year=${e?.year} creator=${e?.creator} pop=${e?.popularity}';
  });
  final seed = search == null ? null : parseSearch(search).firstOrNull;
  if (seed == null) {
    stderr.writeln('Search failed, cannot continue.\n${rows.join('\n')}');
    exit(1);
  }
  final second = (await client.get('/search', {'query': 'The Starless Sea', 'types': ['urn:entity:book'], 'take': 3})
          .then(parseSearch)
          .catchError((_) => <Entity>[]))
      .firstOrNull;
  final signal = [seed.id, if (second != null) second.id];

  await check('entities lookup', '/entities', {'entity_ids': [seed.id]}, (j) => '${parseEntities(j).length} entities');
  await check('tags search', '/v2/tags', {'filter.query': 'dark academia', 'filter.parents.types': 'urn:entity:book', 'take': 5},
      (j) => parseTags(j).take(3).map((t) => '${t.name} <${t.id}>').join(', '));
  final books = await check(
      'insights books + recency + explainability',
      '/v2/insights',
      {
        'filter.type': 'urn:entity:book',
        'signal.interests.entities': signal,
        'filter.exclude.entities': signal,
        'filter.publication_year.min': DateTime.now().year - 5,
        'feature.explainability': true,
        'take': 20,
      },
      entities);
  await check('insights books below top 0.1%', '/v2/insights',
      {'filter.type': 'urn:entity:book', 'signal.interests.entities': signal, 'filter.popularity.max': 0.999, 'take': 10}, entities);
  final candidates = books == null ? <String>[] : parseInsightsEntities(books).take(3).map((e) => e.id).toList();
  if (candidates.isNotEmpty) {
    await check('insights filter.results.entities', '/v2/insights',
        {'filter.type': 'urn:entity:book', 'signal.interests.entities': [seed.id], 'filter.results.entities': candidates, 'take': 3},
        entities);
  }
  await check('insights movies + release_year.min', '/v2/insights',
      {'filter.type': 'urn:entity:movie', 'signal.interests.entities': signal, 'filter.release_year.min': 2018, 'take': 5}, entities);
  await check('insights tv + latest_known_year.min', '/v2/insights',
      {'filter.type': 'urn:entity:tv_show', 'signal.interests.entities': signal, 'filter.latest_known_year.min': 2020, 'take': 5},
      entities);
  for (final type in ['urn:entity:videogame', 'urn:entity:video_game']) {
    await check('insights games ($type)', '/v2/insights', {'filter.type': type, 'signal.interests.entities': signal, 'take': 5}, entities,
        critical: false);
  }
  for (final type in ['artist', 'podcast', 'person', 'brand']) {
    await check('insights $type', '/v2/insights', {'filter.type': 'urn:entity:$type', 'signal.interests.entities': signal, 'take': 5},
        entities);
  }
  await check('insights age-weighted', '/v2/insights', {
    'filter.type': 'urn:entity:book',
    'signal.interests.entities': signal,
    'signal.demographics.age': ['25_to_29', '30_to_34'],
    'take': 5,
  }, entities);
  await check('demographics', '/v2/insights', {'filter.type': 'urn:demographics', 'signal.interests.entities': signal}, (j) {
    final d = parseDemographics(j);
    return d == null ? 'no demographics' : 'ages ${d.age.map((k, v) => MapEntry(k.label, v.toStringAsFixed(2)))} male=${d.male}';
  });
  await check('taste tags', '/v2/insights',
      {'filter.type': 'urn:tag', 'signal.interests.entities': signal, 'filter.parents.types': 'urn:entity:book', 'take': 10},
      (j) => parseTags(j).where(isDescriptiveTag).take(6).map((t) => t.name).join(', '));
  await check('heatmap United States', '/v2/insights',
      {'filter.type': 'urn:heatmap', 'filter.location.query': 'United States', 'signal.interests.entities': signal}, (j) {
    final cells = parseHeatmap(j);
    final cities = aggregateMarkets(cells, citiesFor('US'));
    return '${cells.length} cells -> ${cities.take(5).map((m) => '${m.name}(${m.label})').join(', ')}';
  });
  if (second != null) {
    await check('analysis compare', '/v2/analysis/compare',
        {'a.signal.interests.entities': [seed.id], 'b.signal.interests.entities': [second.id]},
        (j) => '${parseCompare(j).length} tags: ${parseCompare(j).take(5).map((t) => t.name).join(', ')}', critical: false);
  }

  stdout.writeln('\nQloo contract probe against ${config.qlooBaseUrl}\n');
  rows.forEach(stdout.writeln);
  stdout.writeln('\nVideo game type accepted: ${client.videoGameUrn}');
  stdout.writeln('Monthly quota remaining: ${client.monthRemaining ?? 'not reported'}');
  stdout.writeln('Raw (trimmed) responses: ${outDir.path}');
  client.close();
  exit(failures == 0 ? 0 : 1);
}

/// Keeps payloads readable: first 3 list items, long strings shortened.
Object? _trim(Object? v, [int depth = 0]) {
  if (v is Map) return v.map((k, x) => MapEntry(k, k == 'akas' || k == 'short_descriptions' ? '[…]' : _trim(x, depth + 1)));
  if (v is List) return [...v.take(3).map((x) => _trim(x, depth + 1)), if (v.length > 3) '… ${v.length - 3} more'];
  if (v is String && v.length > 200) return '${v.substring(0, 200)}…';
  return v;
}
