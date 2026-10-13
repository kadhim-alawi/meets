import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:meets_core/meets_core.dart';
import 'package:meets_server/meets_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

QlooClient previewClient() => QlooClient(apiKey: 'preview', mode: 'preview', transport: previewTransport, minInterval: Duration.zero);

/// Like the live API: a scoring request (no themes or ages in the signal)
/// returns lower affinities than the main scan for the very same titles.
QlooClient scaledClient() => QlooClient(apiKey: 'preview', mode: 'preview', minInterval: Duration.zero, transport: (uri, headers) async {
      final res = await previewTransport(uri, headers);
      if (!uri.queryParameters.containsKey('filter.results.entities')) return res;
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      for (final e in (json['results'] as Map<String, dynamic>)['entities'] as List) {
        final q = (e as Map<String, dynamic>)['query'] as Map<String, dynamic>;
        q['affinity'] = (q['affinity'] as num) - 0.3;
      }
      return QlooHttpResponse(res.status, jsonEncode(json), res.headers);
    });

const bookBrief = Brief(
  format: WorkFormat.book,
  title: 'The Lantern Archive',
  logline: 'A night-shift archivist discovers the uncatalogued wing rearranges itself around grief.',
  anchors: [AnchorInput(name: 'Piranesi', kind: EntityKind.book), AnchorInput(name: 'The Starless Sea', kind: EntityKind.book)],
  myComps: [AnchorInput(name: "Harry Potter and the Sorcerer's Stone"), AnchorInput(name: 'The Night Circus')],
  recencyYears: 5,
);

/// A fake Messages API: answers the planner, analyst and gut check with tool
/// calls, the way the real model is instructed to.
MockClient fakeAnthropic({List<Json>? captured, List<String> extraTitles = const []}) => MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      captured?.add(body);
      expect(request.headers['x-api-key'], 'test-key');
      expect(body['fallbacks'], 'default');
      final tools = (body['tools'] as List).map((t) => t['name']).toList();
      Map<String, dynamic> toolUse(String name, Map<String, dynamic> input) => {
            'id': 'msg_1',
            'model': body['model'],
            'stop_reason': 'tool_use',
            'content': [
              {'type': 'tool_use', 'id': 'toolu_1', 'name': name, 'input': input},
            ],
            'usage': {'input_tokens': 10, 'output_tokens': 10},
          };
      if (tools.contains('submit_plan')) {
        return http.Response(
            jsonEncode(toolUse('submit_plan', {
              'touchstones': [
                {'name': 'Babel', 'kind': 'book', 'reason': 'dark academia'},
              ],
              'themes': ['dark academia'],
              'reading': 'Literary fantasy for adult readers.',
            })),
            200);
      }
      if (tools.contains('submit_copy')) {
        return http.Response(
            jsonEncode(toolUse('submit_copy', {
              'headline': 'A grief story for readers of {{E1}}.',
              'summary': 'Lead with {{E3}}. Ignore {{E999}}.',
              'pair': {'a': 'E3', 'b': 'E4'},
              'blocks': [
                {'id': 'comp_line', 'body': '{{E3}} meets {{E4}}.'},
                {'id': 'pitch', 'body': '[TITLE], complete at [word count] words, will appeal to readers of {{E3}} and {{E4}}.'},
                {'id': 'not_a_block', 'body': 'ignored'},
              ],
            })),
            200);
      }
      if (tools.contains('submit_titles')) {
        return http.Response(
            jsonEncode(toolUse('submit_titles', {
              'titles': [
                {'name': "Harry Potter and the Sorcerer's Stone"},
                {'name': 'The Night Circus'},
                {'name': 'Babel'},
                {'name': 'A Book That Does Not Exist Anywhere'},
                for (final t in extraTitles) {'name': t},
              ],
            })),
            200);
      }
      return http.Response(jsonEncode({'error': {'message': 'unexpected'}}), 400);
    });

void main() {
  group('CompsAgent (preview transport, no LLM)', () {
    late CompKit kit;
    late ListEmitter emitter;

    setUpAll(() async {
      emitter = ListEmitter();
      kit = await CompsAgent(client: previewClient(), clock: () => DateTime(2026, 10, 9)).build(bookBrief, emitter, kitId: 'k1');
    });

    test('resolves touchstones and scans every category', () {
      expect(kit.mode, 'preview');
      expect(kit.anchors.map((a) => a.name), containsAll(['Piranesi', 'The Starless Sea']));
      expect(kit.primary.kind, EntityKind.book);
      expect(kit.primary.items, isNotEmpty);
      expect(kit.cross.map((s) => s.kind), containsAll([EntityKind.movie, EntityKind.tvShow]));
      expect(kit.primary.items.map((c) => c.entity.id), isNot(contains(kit.anchors.first.id)), reason: 'touchstones are excluded');
    });

    test('respects the recency window as a Qloo filter', () {
      expect(kit.primary.filters.first, startsWith('Published 2021'));
      for (final c in kit.primary.items) {
        expect(c.entity.year ?? 2026, greaterThanOrEqualTo(2016));
      }
    });

    test('chooses a comp line from two different primary comps', () {
      final pair = kit.pairing!;
      expect(pair.a.entity.id, isNot(pair.b.entity.id));
      expect(kit.primary.items.map((c) => c.entity.id), containsAll([pair.a.entity.id, pair.b.entity.id]));
    });

    test('flags the planned comps that are too big or too old', () {
      final hp = kit.compCheck.firstWhere((v) => v.input.startsWith('Harry'));
      expect(hp.verdict, 'swap');
      expect(hp.reasons.join(' '), contains('1997'));
      expect(hp.swap, isNotNull);
      final circus = kit.compCheck.firstWhere((v) => v.input == 'The Night Circus');
      expect(circus.reasons.join(' '), contains('2011'));
    });

    test('writes template copy and targeting lists', () {
      expect(kit.copy.map((c) => c.id), containsAll(['comp_line', 'pitch', 'audience', 'fans_of', 'ad_hooks']));
      expect(kit.copy.every((c) => c.author == 'template'), isTrue);
      expect(kit.targeting.map((t) => t.id), containsAll(['amazon', 'bookbub', 'meta']));
      expect(kit.notes.join(' '), contains('aggregate taste'));
    });

    test('narrates its work, including decisions', () {
      final kinds = emitter.events.map((e) => e.kind).toSet();
      expect(kinds, containsAll(['step', 'qloo', 'decision', 'done']));
      expect(kit.stats.qlooCalls, greaterThan(10));
    });

    test('kit survives a JSON round trip', () {
      final back = CompKit.fromJson(jsonDecode(jsonEncode(kit.toJson())) as Map<String, dynamic>);
      expect(back.primary.items.length, kit.primary.items.length);
      expect(back.pairing!.line, kit.pairing!.line);
    });
  });

  group('with a language model', () {
    test('planner suggestions are verified, copy is grounded, unknown refs removed', () async {
      final captured = <Json>[];
      final llm = LlmClient(apiKey: 'test-key', client: fakeAnthropic(captured: captured));
      final emitter = ListEmitter();
      final kit = await CompsAgent(client: previewClient(), llm: llm, clock: () => DateTime(2026, 10, 9))
          .build(bookBrief, emitter, kitId: 'k2');
      expect(kit.brief.anchors.any((a) => a.suggested && a.name == 'Babel'), isTrue);
      expect(kit.anchors.map((a) => a.name), contains('Babel'));
      final compLine = kit.copy.firstWhere((c) => c.id == 'comp_line');
      expect(compLine.author, 'llm');
      expect(compLine.body, isNot(contains('{{')));
      expect(kit.summary, isNot(contains('E999')));
      expect(kit.copy.map((c) => c.id), isNot(contains('not_a_block')));
      expect(emitter.events.any((e) => e.kind == 'warn' && e.title.contains('could not ground')), isTrue);
      expect(captured.first['model'], 'claude-sonnet-5-5');
      expect(captured.first['output_config'], {'effort': 'low'});
    });

    test('gut check scores the plain LLM picks against Qloo', () async {
      final client = scaledClient();
      // With a model, the planner adds Babel as a touchstone the creator never named.
      final kit = await CompsAgent(client: client, llm: LlmClient(apiKey: 'test-key', client: fakeAnthropic()), clock: () => DateTime(2026, 10, 9))
          .build(bookBrief, ListEmitter(), kitId: 'k3');
      final meetsComp = kit.primary.items.first.entity.name;
      final sent = <Json>[];
      final llm = LlmClient(apiKey: 'test-key', client: fakeAnthropic(captured: sent, extraTitles: ['Piranesi', meetsComp]));
      final result = await GutCheck(llm, client).run(kit, ListEmitter(), currentYear: 2026);
      final verdicts = {for (final i in result.items) i.name: i.verdict};
      expect(verdicts["Harry Potter and the Sorcerer's Stone"], 'too_big');
      expect(verdicts['The Night Circus'], 'dated');
      expect(verdicts['Piranesi'], 'touchstone');
      expect(verdicts['Babel'], 'touchstone');
      // Scored in the same request as Meets' own comps, so one of them can't rank below them all.
      expect(result.items.firstWhere((i) => i.name == meetsComp).fit, greaterThan(0));
      expect(result.summary, contains('of 6'));
      expect(result.summary, contains('2 are already a touchstone in this kit'));
      // The plain model sees only what the creator typed, not Meets' Qloo-verified suggestions.
      final prompt = jsonEncode(sent.single['messages']);
      expect(prompt, contains('Piranesi'));
      expect(prompt, isNot(contains('Babel')));
      expect(prompt, contains('other than those'));
    });
  });

  test('comp check scores your comps on the same scale as Meets\' comps', () async {
    final client = scaledClient();
    final agent = CompsAgent(client: client, clock: () => DateTime(2026, 10, 9));
    final first = await agent.build(bookBrief.copyWith(myComps: const []), ListEmitter(), kitId: 'k4');
    final found = first.primary.items.map((c) => c.entity).toList();
    // Every comp Meets found, entered as the creator's own: none can sit below all of them.
    final kit = await agent.build(
        bookBrief.copyWith(myComps: [for (final e in found.take(5)) AnchorInput(name: e.name, kind: e.kind, id: e.id)]), ListEmitter(),
        kitId: 'k5');
    for (final v in kit.compCheck) {
      expect(v.reasons, isNot(contains('Weaker audience overlap than any comp Meets found.')), reason: v.input);
    }
  });

  group('refine heuristics', () {
    test('reads windows, sizes, markets and drops', () async {
      final kit = await CompsAgent(client: previewClient(), clock: () => DateTime(2026, 10, 9)).build(bookBrief, ListEmitter(), kitId: 'k4');
      final first = kit.primary.items.first.entity.name;
      final r = Refiner.heuristic(kit, 'Only the last 3 years, more indie, for the United Kingdom, and drop $first');
      expect(r.brief.recencyYears, 3);
      expect(r.brief.size, SizePref.indie);
      expect(r.brief.market, 'GB');
      expect(r.brief.excludeIds, contains(kit.primary.items.first.entity.id));
      expect(r.changes, hasLength(4));
    });
  });

  group('HTTP API and MCP', () {
    late Handler handler;
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('meets_test');
      final images = ImageProxy();
      final kits = KitStore(dataDir: tmp.path, images: images);
      final client = previewClient();
      final runs = RunManager(client: client, llm: null, kits: kits, images: images);
      final config = Config.fromEnvironment({'QLOO_MODE': 'preview', 'DATA_DIR': tmp.path, 'PUBLIC_URL': 'https://meets.example'});
      handler = Api(config: config, client: client, runs: runs, kits: kits, images: images, examples: const []).router.call;
    });

    tearDown(() => tmp.delete(recursive: true));

    Future<Json> getJson(String path) async {
      final res = await handler(Request('GET', Uri.parse('http://localhost$path')));
      return jsonDecode(await res.readAsString()) as Json;
    }

    test('health', () async {
      final h = await getJson('/api/health');
      expect(h['qloo'], 'preview');
      expect(h['llm'], false);
    });

    test('rejects a brief without touchstones when no LLM is configured', () async {
      final res = await handler(Request('POST', Uri.parse('http://localhost/api/runs'),
          body: jsonEncode({'brief': const Brief(format: WorkFormat.film, logline: 'A heist movie set on a cruise ship').toJson()})));
      expect(res.statusCode, 400);
    });

    test('starts a run, polls to completion, exports', () async {
      final res = await handler(Request('POST', Uri.parse('http://localhost/api/runs'), body: jsonEncode({'brief': bookBrief.toJson()})));
      expect(res.statusCode, 202);
      final started = jsonDecode(await res.readAsString()) as Json;
      Json snap = {};
      for (var i = 0; i < 100; i++) {
        snap = await getJson('/api/runs/${started['runId']}?after=0');
        if (snap['status'] == 'done' || snap['status'] == 'failed') break;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(snap['status'], 'done');
      expect((snap['events'] as List), isNotEmpty);
      final kitId = started['kitId'];
      final kit = await getJson('/api/kits/$kitId');
      expect(kit['kit']['id'], kitId);
      expect((kit['trace'] as List), isNotEmpty);
      final md = await handler(Request('GET', Uri.parse('http://localhost/api/kits/$kitId/export.md')));
      expect(await md.readAsString(), contains('PREVIEW DATA'));
      final csv = await handler(Request('GET', Uri.parse('http://localhost/api/kits/$kitId/export.csv')));
      expect((await csv.readAsString()).split('\n').first, startsWith('section,category,name'));
      expect(File('${tmp.path}/kits/$kitId.json').existsSync(), isTrue);
    });

    test('MCP initialize, list and call', () async {
      Future<Json> rpc(Json body) async {
        final res = await handler(Request('POST', Uri.parse('http://localhost/mcp'), body: jsonEncode(body)));
        return jsonDecode(await res.readAsString()) as Json;
      }

      final init = await rpc({'jsonrpc': '2.0', 'id': 1, 'method': 'initialize', 'params': {}});
      expect(init['result']['serverInfo']['name'], 'meets');
      final list = await rpc({'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list'});
      expect((list['result']['tools'] as List).map((t) => t['name']), ['find_comps', 'check_comps']);
      final call = await rpc({
        'jsonrpc': '2.0',
        'id': 3,
        'method': 'tools/call',
        'params': {
          'name': 'find_comps',
          'arguments': {'format': 'music', 'touchstones': ['Japanese Breakfast', 'Beach House'], 'size': 'indie'},
        },
      });
      final text = call['result']['content'][0]['text'] as String;
      expect(text, contains('PREVIEW DATA'));
      expect(text, contains('https://meets.example/kit/'));
      expect(call['result']['structuredContent']['comps'], isNotEmpty);
    });
  });
}
