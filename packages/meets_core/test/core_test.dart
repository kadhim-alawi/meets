import 'package:meets_core/meets_core.dart';
import 'package:test/test.dart';

Entity e(String id, {double? pop, double? aff, int? year, List<Driver> drivers = const [], String? creator}) => Entity(
      id: id,
      name: 'Name $id',
      kind: EntityKind.book,
      popularity: pop,
      affinity: aff,
      year: year,
      drivers: drivers,
      creator: creator,
    );

void main() {
  group('SizeBand', () {
    test('reads popularity as top-percent bands', () {
      expect(SizeBand.of(0.99985), SizeBand.blockbuster); // Django Unchained in Qloo's docs
      expect(SizeBand.of(0.9984), SizeBand.breakout); // Everything Everywhere All at Once
      expect(SizeBand.of(0.97), SizeBand.midlist);
      expect(SizeBand.of(0.90), SizeBand.niche);
      expect(SizeBand.of(0.5), SizeBand.deepCut);
      expect(SizeBand.of(null), SizeBand.unknown);
    });

    test('top percent label', () {
      expect(topPercentLabel(0.9984), 'Top 0.16%');
      expect(topPercentLabel(0.97), 'Top 3%');
      expect(topPercentLabel(null), 'Size unknown');
    });
  });

  group('recency', () {
    test('bands relative to the window', () {
      expect(recencyOf(2026, 5, 2026), RecencyBand.fresh);
      expect(recencyOf(2022, 5, 2026), RecencyBand.recent);
      expect(recencyOf(2015, 5, 2026), RecencyBand.dated);
      expect(recencyOf(1990, 5, 2026), RecencyBand.classic);
      expect(recencyOf(1990, 0, 2026), RecencyBand.recent);
      expect(recencyOf(null, 5, 2026), isNull);
    });
  });

  group('scoreCandidates', () {
    test('flags blockbusters, dated picks and weak fits', () {
      final ranked = [
        e('a', pop: 0.9999, aff: 0.95, year: 2024),
        e('b', pop: 0.995, aff: 0.93, year: 2023, drivers: [const Driver(entityId: 'x', score: 0.8)]),
        e('c', pop: 0.98, aff: 0.9, year: 2009),
        e('d', pop: 0.97, aff: 0.6, year: 2025),
      ];
      final scored = scoreCandidates(ranked,
          size: SizePref.breakout, recencyYears: 5, currentYear: 2026, anchorNames: {'x': 'Piranesi'});
      expect(scored[0].flags, contains('too_big'));
      expect(scored[1].flags, isEmpty);
      expect(scored[1].because, ['Piranesi']);
      expect(scored[2].flags, contains('dated'));
      expect(scored[3].fit, lessThan(scored[0].fit));
      expect(rankForDisplay(scored).first.entity.id, 'b');
    });

    test('mainstream preference does not punish blockbusters', () {
      final scored = scoreCandidates([e('a', pop: 0.9999, aff: 0.9, year: 2024)],
          size: SizePref.mainstream, recencyYears: 5, currentYear: 2026, anchorNames: const {});
      expect(scored.single.flags, isEmpty);
    });

    test('cross-domain scans can skip size and recency', () {
      final scored = scoreCandidates([e('a', pop: 0.99999, aff: 0.9, year: 1980)],
          size: SizePref.indie,
          recencyYears: 3,
          currentYear: 2026,
          anchorNames: const {},
          applyRecency: false,
          applySize: false);
      expect(scored.single.flags, isEmpty);
    });
  });

  group('choosePairing', () {
    test('prefers distinct strong comps over near-duplicates', () {
      final ranked = [
        e('a', pop: 0.995, aff: 0.95, year: 2024, creator: 'Same'),
        e('b', pop: 0.994, aff: 0.94, year: 2024, creator: 'Same'),
        e('c', pop: 0.993, aff: 0.93, year: 2024),
      ];
      final scored = scoreCandidates(ranked,
          size: SizePref.breakout, recencyYears: 5, currentYear: 2026, anchorNames: const {});
      final sims = {'a|b': 0.98, 'a|c': 0.4, 'b|c': 0.45};
      final pair = choosePairing(scored, (x, y) => sims['$x|$y'])!;
      expect({pair.a.entity.id, pair.b.entity.id}, {'a', 'c'});
      expect(pair.line, contains(' meets '));
    });

    test('needs two candidates', () {
      final scored = scoreCandidates([e('a', pop: 0.99)],
          size: SizePref.breakout, recencyYears: 5, currentYear: 2026, anchorNames: const {});
      expect(choosePairing(scored, (_, __) => null), isNull);
    });
  });

  group('markets', () {
    test('rolls cells up to cities and labels hidden gems', () {
      final cells = [
        const HeatCell(lat: 40.72, lon: -73.99, affinity: 1, affinityRank: 0.99, popularity: 0.99),
        const HeatCell(lat: 44.48, lon: -73.21, affinity: 0.95, affinityRank: 0.93, popularity: 0.6),
        const HeatCell(lat: 0, lon: 0, affinity: 0.9, affinityRank: 0.9, popularity: 0.1),
      ];
      final markets = aggregateMarkets(cells, citiesFor('US'));
      expect(markets.map((m) => m.name), containsAll(['New York', 'Burlington']));
      expect(markets.firstWhere((m) => m.name == 'Burlington').label, 'hidden_gem');
      expect(markets.firstWhere((m) => m.name == 'New York').label, 'stronghold');
      expect(markets.length, 2);
    });
  });

  group('audience', () {
    test('describes skew', () {
      const profile = AudienceProfile(
        age: {AgeBand.from25to29: 0.4, AgeBand.from30to34: 0.3, AgeBand.over55: -0.3},
        male: -0.2,
        female: 0.2,
      );
      expect(describeAudience(profile, 'readers'), 'Your readers skew 25–34 and lean female.');
    });
  });

  group('json', () {
    test('kit round-trips', () {
      final brief = Brief(
        format: WorkFormat.book,
        title: 'The Lantern Archive',
        logline: 'A librarian discovers a door in the stacks.',
        anchors: const [AnchorInput(name: 'Piranesi', kind: EntityKind.book, id: 'p1')],
        ages: const [AgeBand.from25to29],
      );
      final scored = scoreCandidates([e('a', pop: 0.995, aff: 0.9, year: 2023)],
          size: SizePref.breakout, recencyYears: 5, currentYear: 2026, anchorNames: const {});
      final kit = CompKit(
        id: 'k1',
        createdAt: DateTime.utc(2026, 10, 9),
        brief: brief,
        mode: 'live',
        primary: DomainScan(kind: EntityKind.book, role: 'primary', items: scored, filters: const ['Published 2021+']),
        audience: const AudienceProfile(age: {AgeBand.under25: 0.2}, male: 0.1, female: -0.1),
        markets: const [
          MarketCity(name: 'Austin', country: 'US', lat: 1, lon: 2, affinity: 0.9, popularity: 0.5, cells: 3, label: 'hidden_gem')
        ],
        copy: const [CopyBlock(id: 'comp_line', title: 'Comp line', body: 'A meets B')],
      );
      final back = CompKit.fromJson(kit.toJson());
      expect(back.brief.title, 'The Lantern Archive');
      expect(back.brief.anchors.single.kind, EntityKind.book);
      expect(back.brief.ages.single, AgeBand.from25to29);
      expect(back.primary.items.single.entity.popularity, 0.995);
      expect(back.audience!.age[AgeBand.under25], 0.2);
      expect(back.markets.single.label, 'hidden_gem');
      expect(back.ledger.keys, contains('a'));
    });

    test('brief validation', () {
      expect(const Brief(format: WorkFormat.film).problems(), isNotEmpty);
      expect(const Brief(format: WorkFormat.film, anchors: [AnchorInput(name: 'Heat')]).problems(), isEmpty);
    });

    test('entity kinds map both game spellings', () {
      expect(EntityKind.fromUrn('urn:entity:video_game'), EntityKind.videoGame);
      expect(EntityKind.fromUrn('urn:entity:videogame'), EntityKind.videoGame);
      expect(EntityKind.fromUrn('urn:entity:author'), EntityKind.person);
    });
  });
}
