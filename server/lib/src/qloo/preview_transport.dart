import 'dart:convert';
import 'dart:math' as math;

import 'package:meets_core/meets_core.dart';

import 'qloo_client.dart';

/// PREVIEW ONLY. Serves Qloo-shaped sample responses so the app can be built
/// and demoed without an API key. Titles are real works; every score is a
/// deterministic placeholder, NOT Qloo data. The server only uses this when
/// `QLOO_MODE=preview` is set explicitly, and every kit it produces is marked
/// `mode: preview`, which the app shows as a banner.

int _hash(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h;
}

double _unit(String s) => (_hash(s) % 100000) / 100000.0;

class _Item {
  _Item(this.kind, this.name, this.creator, this.year, this.tags, {this.big = false});

  final EntityKind kind;
  final String name;
  final String? creator;
  final int? year;
  final List<String> tags;
  final bool big;

  String get id {
    final h = _hash('${kind.name}|$name').toRadixString(16).padLeft(8, '0').toUpperCase();
    final h2 = _hash('$name|${kind.name}|x').toRadixString(16).padLeft(8, '0').toUpperCase();
    return '$h-${h2.substring(0, 4)}-4${h2.substring(4, 7)}-8${h.substring(0, 3)}-$h2${h.substring(4)}';
  }

  /// Placeholder popularity spread across Meets' size bands.
  double get popularity {
    if (big) return 0.99995 - _unit('pop$name') * 0.00004;
    final top = math.pow(10, -1.6 + _unit('pop$name') * 2.6); // 0.025% .. 10%
    return 1 - top / 100;
  }
}

List<_Item> _parse(EntityKind kind, String block) => block
    .trim()
    .split('\n')
    .map((line) => line.split('|'))
    .map((f) => _Item(
          kind,
          f[0].trim(),
          f[1].trim().isEmpty ? null : f[1].trim(),
          int.tryParse(f[2].trim()),
          f[3].split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList(),
          big: f.length > 4 && f[4].trim() == 'big',
        ))
    .toList();

final List<_Item> _catalog = [
  ..._parse(EntityKind.book, '''
Piranesi|Susanna Clarke|2020|fantasy,literary fiction,mystery
The Starless Sea|Erin Morgenstern|2019|fantasy,literary fiction,magical realism
The Night Circus|Erin Morgenstern|2011|fantasy,romance,magical realism
Babel|R. F. Kuang|2022|dark academia,fantasy,historical fiction
The Atlas Six|Olivie Blake|2022|dark academia,fantasy
Ninth House|Leigh Bardugo|2019|dark academia,fantasy,mystery
The Invisible Life of Addie LaRue|V. E. Schwab|2020|fantasy,romance,literary fiction
Tomorrow, and Tomorrow, and Tomorrow|Gabrielle Zevin|2022|literary fiction,friendship
Sea of Tranquility|Emily St. John Mandel|2022|science fiction,literary fiction
Station Eleven|Emily St. John Mandel|2014|science fiction,literary fiction
The Ten Thousand Doors of January|Alix E. Harrow|2019|fantasy,portal fantasy
Legends & Lattes|Travis Baldree|2022|cozy fantasy,fantasy
The House in the Cerulean Sea|TJ Klune|2020|cozy fantasy,found family
Emily Wilde's Encyclopaedia of Faeries|Heather Fawcett|2023|cozy fantasy,dark academia
The Spellshop|Sarah Beth Durst|2024|cozy fantasy,romance
A Psalm for the Wild-Built|Becky Chambers|2021|cozy fantasy,science fiction
The Midnight Library|Matt Haig|2020|literary fiction,magical realism
Mexican Gothic|Silvia Moreno-Garcia|2020|gothic,horror
Harry Potter and the Sorcerer's Stone|J. K. Rowling|1997|fantasy,coming of age|big
Fourth Wing|Rebecca Yarros|2023|romantasy,fantasy|big
'''),
  ..._parse(EntityKind.movie, '''
Palm Springs|Max Barbakow|2020|comedy,time loop,romance
Ready or Not|Matt Bettinelli-Olpin|2019|horror,comedy
Happy Death Day|Christopher Landon|2017|horror,comedy,time loop
Barbarian|Zach Cregger|2022|horror
Bodies Bodies Bodies|Halina Reijn|2022|horror,comedy
Freaky|Christopher Landon|2020|horror,comedy
The Menu|Mark Mylod|2022|horror,satire
Talk to Me|Danny Philippou|2023|horror
Past Lives|Celine Song|2023|romance,drama
Saltburn|Emerald Fennell|2023|thriller,satire
The Substance|Coralie Fargeat|2024|horror,satire
Arrival|Denis Villeneuve|2016|science fiction,drama
Knives Out|Rian Johnson|2019|mystery,comedy
Groundhog Day|Harold Ramis|1993|comedy,time loop
Everything Everywhere All at Once|Daniels|2022|comedy,science fiction|big
'''),
  ..._parse(EntityKind.tvShow, '''
Ted Lasso|Apple TV+|2020|comedy,sports
Abbott Elementary|ABC|2021|comedy,workplace comedy
The Bear|FX|2022|drama,workplace comedy
What We Do in the Shadows|FX|2019|comedy,horror
Severance|Apple TV+|2022|science fiction,workplace
Only Murders in the Building|Hulu|2021|comedy,mystery
Brooklyn Nine-Nine|NBC|2013|comedy,workplace comedy
Somebody Somewhere|HBO|2022|comedy,drama
Shrinking|Apple TV+|2023|comedy,drama
Reservation Dogs|FX|2021|comedy,drama
Hacks|HBO|2021|comedy,stand-up
Welcome to Wrexham|FX|2022|documentary,sports
Sunderland 'Til I Die|Netflix|2018|documentary,sports
Fleabag|BBC|2016|comedy,drama
The Office|NBC|2005|comedy,workplace comedy|big
'''),
  ..._parse(EntityKind.artist, '''
Japanese Breakfast||2016|indie pop,dream pop
Beach House||2006|dream pop,indie
Alvvays||2014|indie pop,shoegaze
Mitski||2012|indie rock,art pop
Phoebe Bridgers||2017|indie folk
Men I Trust||2014|dream pop,indie pop
Clairo||2017|bedroom pop,indie pop
Soccer Mommy||2017|indie rock
Caroline Polachek||2019|art pop,synth-pop
Magdalena Bay||2019|synth-pop,electropop
Faye Webster||2017|indie folk,indie pop
MUNA||2016|synth-pop
Khruangbin||2015|psychedelic,funk
boygenius||2018|indie rock
Taylor Swift||2006|pop|big
'''),
  ..._parse(EntityKind.videoGame, '''
Slay the Spire|Mega Crit|2019|roguelike,deckbuilder
Spiritfarer|Thunder Lotus|2020|cozy,management
Unpacking|Witch Beam|2021|cozy,puzzle
Hades|Supergiant Games|2020|roguelike,action
Balatro|LocalThunk|2024|roguelike,deckbuilder
Inscryption|Daniel Mullins|2021|deckbuilder,horror
Cult of the Lamb|Massive Monster|2022|roguelike,management
A Short Hike|adamgryu|2019|cozy,exploration
Dorfromantik|Toukana|2022|cozy,puzzle
Coffee Talk|Toge Productions|2020|cozy,visual novel
Monster Train|Shiny Shoe|2020|roguelike,deckbuilder
Wildfrost|Deadpan Games|2023|roguelike,deckbuilder,cozy
Potion Craft|niceplay games|2021|cozy,management
Stardew Valley|ConcernedApe|2016|cozy,farming|big
'''),
  ..._parse(EntityKind.podcast, '''
How I Built This|Guy Raz||business,entrepreneurship
Acquired|Ben Gilbert & David Rosenthal||business,technology
This Week in Startups|Jason Calacanis||startups,technology
Masters of Scale|Reid Hoffman||business,entrepreneurship
My First Million|Shaan Puri & Sam Parr||business,entrepreneurship
Founders|David Senra||business,history
20VC|Harry Stebbings||venture capital
Lenny's Podcast|Lenny Rachitsky||product,startups
Pivot|Kara Swisher & Scott Galloway||technology,business
Hard Fork|Kevin Roose & Casey Newton||technology
Planet Money|NPR||economics
Startup|Gimlet||startups,narrative
The Joe Rogan Experience|Joe Rogan||comedy,interviews|big
'''),
  ..._parse(EntityKind.person, '''
Cedric the Entertainer|||comedian,actor,stand-up
Steve Harvey|||comedian,host
Nate Bargatze|||comedian,stand-up,clean comedy
Jim Gaffigan|||comedian,clean comedy,stand-up
Sebastian Maniscalco|||comedian,stand-up
Taylor Tomlinson|||comedian,stand-up
John Mulaney|||comedian,stand-up
Ali Wong|||comedian,stand-up
Bernie Mac|||comedian,actor
D.L. Hughley|||comedian,stand-up
Mike Epps|||comedian,actor
Gabriel Iglesias|||comedian,stand-up
Hasan Minhaj|||comedian,stand-up
Kevin Hart|||comedian,actor|big
'''),
  ..._parse(EntityKind.brand, '''
Patagonia|||outdoor,apparel
Liquid Death|||beverages
Oatly|||food,beverages
Glossier|||beauty
Notion|||software,productivity
Duolingo|||education,apps
A24|||film studio
The Criterion Collection|||film,home video
Moleskine|||stationery
Bookshop.org|||books,retail
Audible|||audiobooks
Nintendo|||video games
Uniqlo|||apparel
Muji|||home goods
'''),
];

final Map<String, _Item> _byId = {for (final i in _catalog) i.id: i};
final Map<String, _Item> _synthetic = {};

String _slug(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_|_$'), '');

Json _tagJson(String name, String family, String domain) =>
    {'id': 'urn:tag:$family:$domain:${_slug(name)}', 'name': name, 'type': 'urn:tag:$family:$domain'};

String _domain(EntityKind k) => switch (k) {
      EntityKind.artist => 'music',
      EntityKind.book => 'book',
      EntityKind.videoGame => 'videogame',
      EntityKind.brand => 'brand',
      EntityKind.podcast => 'podcast',
      EntityKind.person => 'person',
      _ => 'media',
    };

Json _entityJson(_Item i, {double? affinity, List<String> signal = const []}) {
  final props = <String, dynamic>{
    if (i.year != null) (i.kind == EntityKind.book ? 'publication_year' : 'release_year'): i.year,
    if (i.creator != null) (i.kind == EntityKind.book ? 'author' : 'creator'): i.creator,
    'description': 'Preview sample entry for ${i.name}. Not Qloo data.',
  };
  return {
    'name': i.name,
    'entity_id': i.id,
    'type': 'urn:entity',
    'subtype': i.kind.urn,
    'types': [i.kind.urn],
    'popularity': i.popularity,
    'properties': props,
    'tags': [for (final t in i.tags) _tagJson(_title(t), 'genre', _domain(i.kind))],
    if (affinity != null)
      'query': {
        'affinity': affinity,
        'explainability': {
          'signal.interests.entities': [
            for (final s in signal.take(3)) {'entity_id': s, 'score': double.parse((0.2 + _unit('$s${i.id}') * 0.8).toStringAsFixed(3))},
          ],
        },
      },
  };
}

String _title(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

_Item? _lookup(String id) => _byId[id] ?? _synthetic[id];

QlooHttpResponse _ok(Object body) => QlooHttpResponse(200, jsonEncode(body));

List<String> _list(String? v) => (v ?? '').split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

/// The preview transport. Drop-in replacement for the HTTP transport.
Future<QlooHttpResponse> previewTransport(Uri uri, Map<String, String> headers) async {
  await Future<void>.delayed(Duration(milliseconds: 120 + _hash(uri.toString()) % 260));
  final q = uri.queryParameters;
  final path = uri.path.replaceFirst(RegExp(r'^/+'), '/');
  switch (path) {
    case '/search':
      final query = (q['query'] ?? '').toLowerCase().trim();
      final kinds = _list(q['types']).map(EntityKind.fromUrn).toSet();
      final hits = _catalog
          .where((i) => (kinds.isEmpty || kinds.contains(i.kind)) && i.name.toLowerCase().contains(query))
          .toList()
        ..sort((a, b) => b.popularity.compareTo(a.popularity));
      if (hits.isEmpty && query.length > 1) {
        final kind = kinds.isEmpty ? EntityKind.book : kinds.first;
        final name = query.split(' ').map(_title).join(' ');
        final item = _Item(kind, name, null, 2018 + _hash(name) % 7, const ['sample']);
        _synthetic[item.id] = item;
        hits.add(item);
      }
      return _ok({'results': hits.take(int.tryParse(q['take'] ?? '') ?? 6).map(_entityJson).toList()});
    case '/entities':
      final items = _list(q['entity_ids']).map(_lookup).whereType<_Item>().toList();
      return _ok({'results': items.map(_entityJson).toList()});
    case '/v2/tags':
      final query = q['filter.query'] ?? 'theme';
      return _ok({
        'results': {
          'tags': [
            _tagJson(_title(query), 'keyword', 'media'),
            _tagJson('${_title(query)} fiction', 'genre', 'media'),
          ],
        },
      });
    case '/v2/analysis/compare':
      final a = _list(q['a.signal.interests.entities']).map(_lookup).whereType<_Item>();
      final b = _list(q['b.signal.interests.entities']).map(_lookup).whereType<_Item>();
      final shared = {...a.expand((i) => i.tags)}.intersection({...b.expand((i) => i.tags)});
      final tags = (shared.isEmpty ? {'storytelling', 'character driven'} : shared).toList();
      return _ok({
        'results': {
          'tags': [for (final t in tags) {..._tagJson(_title(t), 'genre', 'media'), 'query': {'affinity': 0.8}}],
        },
      });
    case '/v2/insights':
      return _insights(q);
  }
  return const QlooHttpResponse(404, '{"error":"not found"}');
}

QlooHttpResponse _insights(Map<String, String> q) {
  final type = q['filter.type'] ?? '';
  final signal = _list(q['signal.interests.entities']);
  final key = signal.join(',');
  if (type == 'urn:demographics') {
    return _ok({
      'results': {
        'demographics': [
          for (final s in signal)
            {
              'entity_id': s,
              'query': {
                'age': {for (final band in AgeBand.values) band.key: double.parse(((_unit('${band.key}$s') - 0.45) * 1.1).toStringAsFixed(2))},
                'gender': () {
                  final f = double.parse(((_unit('g$s') - 0.4) * 0.6).toStringAsFixed(2));
                  return {'female': f, 'male': -f};
                }(),
              },
            },
        ],
      },
    });
  }
  if (type == 'urn:tag') {
    final items = signal.map(_lookup).whereType<_Item>();
    final names = {
      ...items.expand((i) => i.tags),
      'character driven', 'witty dialogue', 'slow burn', 'atmospheric', 'bittersweet', 'clever', 'quirky', 'melancholy',
    }.toList()
      ..sort((a, b) => _unit('$key$b').compareTo(_unit('$key$a')));
    return _ok({
      'results': {
        'tags': [
          for (final n in names.take(int.tryParse(q['take'] ?? '') ?? 20))
            {
              'tag_id': 'urn:tag:keyword:media:${_slug(n)}',
              'name': n,
              'subtype': 'urn:tag:keyword:media',
              'query': {'affinity': double.parse((0.6 + _unit('$key$n') * 0.4).toStringAsFixed(3))},
            },
        ],
      },
    });
  }
  if (type == 'urn:heatmap') {
    final market = Market.all.firstWhere((m) => m.query == q['filter.location.query'], orElse: () => Market.all.first);
    final cells = <Json>[];
    for (final city in citiesFor(market.code)) {
      final n = 1 + _hash('${city.name}$key') % 3;
      for (var i = 0; i < n; i++) {
        final aff = _unit('${city.name}$key$i');
        cells.add({
          'location': {
            'latitude': city.lat + (_unit('lat${city.name}$i') - 0.5) * 0.2,
            'longitude': city.lon + (_unit('lon${city.name}$i') - 0.5) * 0.2,
            'geohash': 'preview',
          },
          'query': {
            'affinity': aff,
            'affinity_rank': double.parse((0.55 + aff * 0.45).toStringAsFixed(4)),
            'popularity': double.parse((_unit('pop${city.name}') * 0.95).toStringAsFixed(4)),
          },
        });
      }
    }
    return _ok({'results': {'heatmap': cells}});
  }
  final kind = EntityKind.fromUrn(type);
  final exclude = _list(q['filter.exclude.entities']).toSet();
  final only = _list(q['filter.results.entities']).toSet();
  final popMax = double.tryParse(q['filter.popularity.max'] ?? '');
  final minYear = int.tryParse(q['filter.publication_year.min'] ?? q['filter.release_year.min'] ?? q['filter.latest_known_year.min'] ?? '');
  var pool = [..._catalog, ..._synthetic.values].where((i) => i.kind == kind && !exclude.contains(i.id));
  if (only.isNotEmpty) pool = pool.where((i) => only.contains(i.id));
  if (popMax != null) pool = pool.where((i) => i.popularity <= popMax);
  if (minYear != null) pool = pool.where((i) => i.year == null || i.year! >= minYear);
  final scored = pool.map((i) => (i, 0.55 + _unit('$key|${i.id}') * 0.43)).toList()..sort((a, b) => b.$2.compareTo(a.$2));
  final take = int.tryParse(q['take'] ?? '') ?? 20;
  return _ok({
    'success': true,
    'results': {
      'entities': [for (final (i, a) in scored.take(take)) _entityJson(i, affinity: double.parse(a.toStringAsFixed(4)), signal: signal)],
    },
  });
}
