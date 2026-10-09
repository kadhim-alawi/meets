import 'dart:convert';

import 'package:meets_core/meets_core.dart';
import 'package:meets_server/meets_server.dart';
import 'package:test/test.dart';

/// Response shapes copied from Qloo's public documentation (qloo/docs-public).
const docsInsights = {
  'success': true,
  'results': {
    'entities': [
      {
        'name': 'Everything Everywhere All at Once',
        'entity_id': 'F0D354AA-BA7E-49D2-8ABA-9A8250F5C852',
        'type': 'urn:entity',
        'subtype': 'urn:entity:movie',
        'properties': {
          'release_year': 2022,
          'release_date': '2022-04-08',
          'description': 'A middle-aged Chinese immigrant is swept up into an insane adventure.',
          'image': {'url': 'https://staging.images.qloo.com/i/F0D354AA-420x-outside.jpg'},
        },
        'popularity': 0.9984116946335868,
        'tags': [
          {'id': 'urn:tag:streaming_service:media:neon_tv', 'name': 'Neon Tv', 'type': 'urn:tag:streaming_service:media'},
          {'id': 'urn:tag:keyword:media:multiverse', 'name': 'Multiverse', 'type': 'urn:tag:keyword:media'},
        ],
        'query': {
          'affinity': 0.91,
          'explainability': {
            'signal.interests.entities': [
              {'entity_id': 'AAA', 'score': 0.8},
              {'entity_id': 'BBB', 'score': 0.05},
            ],
          },
        },
      },
    ],
  },
  'duration': 22,
};

const docsDemographics = {
  'success': true,
  'results': {
    'demographics': [
      {
        'entity_id': 'urn:tag:genre:media:action',
        'query': {
          'age': {'24_and_younger': 0, '25_to_29': 0.43, '30_to_34': 0.23, '35_to_44': -0.02, '45_to_54': -0.28, '55_and_older': -0.17},
          'gender': {'male': 0.08, 'female': -0.08},
        },
      },
      {
        'entity_id': 'B8BEE72B-B321-481F-B81A-A44881D094D6',
        'query': {
          'age': {'24_and_younger': -0.09, '25_to_29': 0.36, '30_to_34': 0.7, '35_to_44': 0.17, '45_to_54': -0.53, '55_and_older': -0.32},
          'gender': {'male': 0.16, 'female': -0.16},
        },
      },
    ],
  },
};

const docsHeatmap = {
  'success': true,
  'results': {
    'heatmap': [
      {
        'location': {'latitude': 40.591736, 'longitude': -73.756714, 'geohash': 'dr5wct'},
        'query': {'affinity': 1, 'affinity_rank': 0.9976498237367802, 'popularity': 0.9717472118959107},
      },
      {
        'location': {'latitude': 40.73456, 'longitude': -73.83362, 'geohash': 'dr5rxz'},
        'query': {'affinity': 0.995539033457249, 'affinity_rank': 0.9939903846153846, 'popularity': 0.2312267657992565},
      },
    ],
  },
};

const docsTasteTags = {
  'success': true,
  'results': {
    'tags': [
      {
        'tag_id': 'urn:tag:keyword:media:cultural_clash',
        'name': 'Cultural Clash',
        'types': ['urn:entity:movie'],
        'subtype': 'urn:tag:keyword:media',
        'tag_value': 'urn:tag:keyword:media:cultural_clash',
        'query': {},
      },
      {
        'tag_id': 'urn:tag:streaming_service:media:apple_tv',
        'name': 'Apple Tv',
        'subtype': 'urn:tag:streaming_service:media',
      },
    ],
  },
};

void main() {
  group('QlooClient params', () {
    test('rejects undocumented parameter names', () {
      expect(() => QlooClient.cleanParams({'filter.type': 'urn:entity:movie', 'signal_interests': 'x'}), throwsArgumentError);
    });

    test('encodes lists, bools and doubles; drops empties; sorts keys', () {
      final clean = QlooClient.cleanParams({
        'take': 10,
        'signal.interests.entities': ['a', 'b'],
        'feature.explainability': true,
        'filter.popularity.max': 0.999,
        'filter.tags': <String>[],
        'filter.location.query': '',
        'a.signal.interests.entities': ['x'],
      });
      expect(clean, {
        'a.signal.interests.entities': 'x',
        'feature.explainability': 'true',
        'filter.popularity.max': '0.999',
        'signal.interests.entities': 'a,b',
        'take': '10',
      });
    });
  });

  group('QlooClient transport behaviour', () {
    test('sends the key header, caches, and shares in-flight calls', () async {
      var calls = 0;
      Map<String, String>? seenHeaders;
      final client = QlooClient(
        apiKey: 'secret',
        minInterval: Duration.zero,
        transport: (uri, headers) async {
          calls++;
          seenHeaders = headers;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return QlooHttpResponse(200, jsonEncode(docsInsights));
        },
      );
      final params = {'filter.type': 'urn:entity:movie', 'signal.interests.entities': ['x']};
      final results = await Future.wait([client.get('/v2/insights', params), client.get('/v2/insights', params)]);
      expect(results, hasLength(2));
      expect(calls, 1);
      expect(seenHeaders!['X-Api-Key'], 'secret');
      await client.get('/v2/insights', params);
      expect(calls, 1, reason: 'third call is served from cache');
    });

    test('retries 429 then succeeds', () async {
      var calls = 0;
      final client = QlooClient(
        apiKey: 'k',
        minInterval: Duration.zero,
        transport: (uri, headers) async {
          calls++;
          if (calls == 1) return const QlooHttpResponse(429, '{}', {'x-second-ratelimit-reset': '0.1'});
          return const QlooHttpResponse(200, '{"results":[]}', {'x-month-ratelimit-remaining': '9876'});
        },
      );
      await client.get('/search', {'query': 'x'});
      expect(calls, 2);
      expect(client.monthRemaining, 9876);
    });

    test('surfaces 4xx as QlooException with the message', () async {
      final client = QlooClient(
        apiKey: 'k',
        minInterval: Duration.zero,
        transport: (uri, headers) async => const QlooHttpResponse(401, '{"error":{"message":"invalid key"}}'),
      );
      expect(
        () => client.get('/search', {'query': 'x'}),
        throwsA(isA<QlooException>().having((e) => e.status, 'status', 401).having((e) => e.message, 'message', 'invalid key')),
      );
    });

    test('falls back to the other video game spelling on 400', () async {
      final seen = <String>[];
      final client = QlooClient(
        apiKey: 'k',
        minInterval: Duration.zero,
        transport: (uri, headers) async {
          final type = uri.queryParameters['filter.type']!;
          seen.add(type);
          if (type == 'urn:entity:videogame') return const QlooHttpResponse(400, '{"error":"bad type"}');
          return const QlooHttpResponse(200, '{"results":{"entities":[]}}');
        },
      );
      await client.get('/v2/insights', {'filter.type': 'urn:entity:videogame', 'signal.interests.entities': ['x']});
      expect(seen, ['urn:entity:videogame', 'urn:entity:video_game']);
      expect(client.videoGameUrn, 'urn:entity:video_game');
    });
  });

  group('parsers (documented shapes)', () {
    test('insights entity', () {
      final e = parseInsightsEntities(docsInsights).single;
      expect(e.name, 'Everything Everywhere All at Once');
      expect(e.kind, EntityKind.movie);
      expect(e.year, 2022);
      expect(e.popularity, closeTo(0.9984, 0.0001));
      expect(e.affinity, 0.91);
      expect(e.imageUrl, contains('images.qloo.com'));
      expect(e.tags.map((t) => t.name), ['Multiverse'], reason: 'streaming services are noise');
      expect(e.drivers.first.entityId, 'AAA');
      expect(SizeBand.of(e.popularity), SizeBand.breakout);
    });

    test('demographics are averaged across signals', () {
      final d = parseDemographics(docsDemographics)!;
      expect(d.age[AgeBand.from30to34], closeTo((0.23 + 0.7) / 2, 1e-9));
      expect(d.male, closeTo(0.12, 1e-9));
      expect(d.coreAges.first, AgeBand.from30to34);
    });

    test('heatmap cells', () {
      final cells = parseHeatmap(docsHeatmap);
      expect(cells, hasLength(2));
      expect(cells.first.affinityRank, closeTo(0.9976, 0.0001));
      final markets = aggregateMarkets(cells, citiesFor('US'));
      expect(markets.single.name, 'New York');
    });

    test('taste-analysis tags use tag_id and drop noisy families', () {
      final tags = parseTags(docsTasteTags).where(isDescriptiveTag).toList();
      expect(tags.single.id, 'urn:tag:keyword:media:cultural_clash');
    });

    test('compare parser finds tags anywhere under results', () {
      final tags = parseCompare({
        'results': {
          'shared': {
            'tags': [
              {'id': 'urn:tag:genre:media:comedy', 'name': 'Comedy', 'type': 'urn:tag:genre:media', 'score': 0.7},
            ],
          },
        },
      });
      expect(tags.single.name, 'Comedy');
      expect(tags.single.score, 0.7);
    });

    test('search results and creators', () {
      final list = parseSearch({
        'results': [
          {
            'entity_id': 'B1',
            'name': 'Piranesi',
            'types': ['urn:entity:book'],
            'popularity': 0.97,
            'properties': {'publication_year': 2020, 'author': 'Susanna Clarke'},
          },
        ],
      });
      expect(list.single.kind, EntityKind.book);
      expect(list.single.creator, 'Susanna Clarke');
      expect(list.single.year, 2020);
    });
  });

  group('matching', () {
    Entity e(String id, String name, EntityKind kind, double pop) => Entity(id: id, name: name, kind: kind, popularity: pop);

    test('prefers exact titles, then the requested kind', () {
      final results = [
        e('1', 'Dune: Part Two', EntityKind.movie, 0.999),
        e('2', 'Dune', EntityKind.movie, 0.998),
        e('3', 'Dune', EntityKind.book, 0.99),
      ];
      expect(pickMatch('Dune', results, kind: EntityKind.book)!.id, '3');
      expect(pickMatch('dune', results)!.id, '2');
    });

    test('rejects unrelated best guesses', () {
      expect(pickMatch('Quiet Ponds', [e('1', 'Loud Mountains', EntityKind.book, 0.9)]), isNull);
    });

    TagRef tag(String family, String name) =>
        TagRef(id: 'urn:tag:$family:media:${name.toLowerCase()}', name: name, type: 'urn:tag:$family:media');

    test('prefers the genre when several tags share the theme name', () {
      final tags = [tag('keyword', 'Jazz'), tag('audience', 'Jazz'), tag('genre', 'Jazz'), tag('genre', 'Jazz Fusion')];
      expect(pickThemeTag('jazz', tags)!.id, 'urn:tag:genre:media:jazz');
    });

    test('falls back to the first descriptive tag when no name matches', () {
      final tags = [tag('audience', 'Night owls'), tag('keyword', 'Heists'), tag('genre', 'Heist thriller')];
      expect(pickThemeTag('heist', tags)!.id, 'urn:tag:keyword:media:heists');
      expect(pickThemeTag('heist', const []), isNull);
    });

    test('merges lists by affinity without duplicates', () {
      final a = [const Entity(id: '1', name: 'A', kind: EntityKind.book, affinity: 0.9)];
      final b = [
        const Entity(id: '2', name: 'B', kind: EntityKind.book, affinity: 0.95),
        const Entity(id: '1', name: 'A', kind: EntityKind.book, affinity: 0.9),
      ];
      expect(mergeByAffinity(a, b).map((x) => x.id), ['2', '1']);
    });
  });
}
