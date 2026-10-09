import 'dart:math' as math;

import 'brief.dart';
import 'cities.dart';
import 'entity.dart';
import 'kinds.dart';
import 'kit.dart';

/// Where an entity sits on Qloo's popularity curve. Qloo popularity is a
/// percentile across every entity of the same type, so we read it as
/// "top X%" rather than as a raw number.
enum SizeBand {
  blockbuster('Blockbuster', 'Top 0.1%'),
  breakout('Breakout', 'Top 0.1–1%'),
  midlist('Mid-list', 'Top 1–5%'),
  niche('Niche', 'Top 5–20%'),
  deepCut('Deep cut', 'Below top 20%'),
  unknown('Unknown size', 'No popularity data');

  const SizeBand(this.label, this.range);

  final String label;
  final String range;

  static SizeBand fromName(String? name) =>
      values.firstWhere((v) => v.name == name, orElse: () => SizeBand.unknown);

  static SizeBand of(double? popularity) {
    if (popularity == null) return SizeBand.unknown;
    final top = (1 - popularity) * 100;
    if (top < 0.1) return SizeBand.blockbuster;
    if (top < 1) return SizeBand.breakout;
    if (top < 5) return SizeBand.midlist;
    if (top < 20) return SizeBand.niche;
    return SizeBand.deepCut;
  }

  /// Bigger index = bigger audience.
  int get bigness => switch (this) {
        SizeBand.blockbuster => 4,
        SizeBand.breakout => 3,
        SizeBand.midlist => 2,
        SizeBand.niche => 1,
        SizeBand.deepCut => 0,
        SizeBand.unknown => 2,
      };
}

enum RecencyBand {
  fresh('Fresh', 'Last 2 years'),
  recent('Recent', 'Inside your window'),
  dated('Dated', 'Older than your window'),
  classic('Classic', 'More than a decade past your window');

  const RecencyBand(this.label, this.help);

  final String label;
  final String help;

  static RecencyBand? fromName(String? name) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    return null;
  }
}

/// How well each size band suits a creator's [SizePref] (0..1).
double sizeWeight(SizeBand band, SizePref pref) => switch (pref) {
      SizePref.indie => const {
          SizeBand.blockbuster: 0.25,
          SizeBand.breakout: 0.6,
          SizeBand.midlist: 1.0,
          SizeBand.niche: 1.0,
          SizeBand.deepCut: 0.8,
          SizeBand.unknown: 0.7,
        }[band]!,
      SizePref.breakout => const {
          SizeBand.blockbuster: 0.4,
          SizeBand.breakout: 1.0,
          SizeBand.midlist: 1.0,
          SizeBand.niche: 0.75,
          SizeBand.deepCut: 0.5,
          SizeBand.unknown: 0.7,
        }[band]!,
      SizePref.mainstream => const {
          SizeBand.blockbuster: 1.0,
          SizeBand.breakout: 1.0,
          SizeBand.midlist: 0.7,
          SizeBand.niche: 0.45,
          SizeBand.deepCut: 0.3,
          SizeBand.unknown: 0.6,
        }[band]!,
    };

/// The size bands a preference aims for, used in copy and filters.
List<SizeBand> targetBands(SizePref pref) => switch (pref) {
      SizePref.indie => [SizeBand.midlist, SizeBand.niche],
      SizePref.breakout => [SizeBand.breakout, SizeBand.midlist],
      SizePref.mainstream => [SizeBand.blockbuster, SizeBand.breakout],
    };

RecencyBand? recencyOf(int? year, int windowYears, int currentYear) {
  if (year == null) return null;
  final age = currentYear - year;
  if (age <= 2) return RecencyBand.fresh;
  if (windowYears <= 0 || age <= windowYears) return RecencyBand.recent;
  if (age <= windowYears + 10) return RecencyBand.dated;
  return RecencyBand.classic;
}

double recencyWeight(RecencyBand? band, int windowYears) {
  if (windowYears <= 0) return 1;
  return switch (band) {
    RecencyBand.fresh || RecencyBand.recent => 1.0,
    RecencyBand.dated => 0.55,
    RecencyBand.classic => 0.3,
    null => 0.8,
  };
}

/// Fit from Qloo's ranked order and affinity. Rank carries most of the
/// signal because Qloo affinities bunch up near the top of a result list.
double fitScore({required int rank, required int total, double? affinity}) {
  final span = math.max(total - 1, 1);
  final rankFit = 1 - ((rank - 1) / span) * 0.6;
  final aff = affinity ?? rankFit;
  return (0.65 * rankFit + 0.35 * aff).clamp(0, 1).toDouble();
}

/// Turns an affinity-ranked Qloo list into scored candidates.
///
/// [anchorNames] maps anchor entity ids to display names, for the "because
/// you said X" explanation. [applyRecency] is false for categories where the
/// creator's recency window should not apply (cross-domain scans).
List<Candidate> scoreCandidates(
  List<Entity> ranked, {
  required SizePref size,
  required int recencyYears,
  required int currentYear,
  required Map<String, String> anchorNames,
  bool applyRecency = true,
  bool applySize = true,
}) {
  final out = <Candidate>[];
  for (var i = 0; i < ranked.length; i++) {
    final e = ranked[i];
    final fit = fitScore(rank: i + 1, total: ranked.length, affinity: e.affinity);
    final band = SizeBand.of(e.popularity);
    final recency = applyRecency ? recencyOf(e.year, recencyYears, currentYear) : null;
    final sw = applySize ? sizeWeight(band, size) : 1.0;
    final rw = applyRecency ? recencyWeight(recency, recencyYears) : 1.0;
    final flags = <String>[];
    if (applySize) {
      final targets = targetBands(size);
      final biggest = targets.map((b) => b.bigness).reduce(math.max);
      final smallest = targets.map((b) => b.bigness).reduce(math.min);
      if (band != SizeBand.unknown && band.bigness > biggest && sw <= 0.6) flags.add('too_big');
      if (band != SizeBand.unknown && band.bigness < smallest && sw <= 0.5) flags.add('too_small');
    }
    if (applyRecency && recencyYears > 0 && (recency == RecencyBand.dated || recency == RecencyBand.classic)) {
      flags.add('dated');
    }
    if (fit < 0.5) flags.add('weak_fit');
    final because = <String>[];
    final drivers = [...e.drivers]..sort((a, b) => b.score.compareTo(a.score));
    for (final d in drivers) {
      final name = anchorNames[d.entityId];
      if (name != null && d.score >= 0.1 && !because.contains(name)) because.add(name);
    }
    out.add(Candidate(
      entity: e,
      fit: fit,
      size: band,
      recency: recency,
      score: (fit * sw * rw).clamp(0, 1).toDouble(),
      flags: flags,
      because: because,
      rank: i + 1,
    ));
  }
  return out;
}

/// Orders candidates for display: sweet spots first, then by score.
List<Candidate> rankForDisplay(List<Candidate> items) {
  final copy = [...items];
  copy.sort((a, b) {
    final sa = a.isSweetSpot ? 1 : 0;
    final sb = b.isSweetSpot ? 1 : 0;
    if (sa != sb) return sb - sa;
    return b.score.compareTo(a.score);
  });
  return copy;
}

/// Picks the "A meets B" pair from scored candidates.
///
/// [similarity] returns Qloo's affinity of B given A (null when unknown). The
/// best pair is two strong, right-sized comps that are *not* the same thing,
/// ideally pulled up by different touchstones.
CompPairing? choosePairing(List<Candidate> candidates, double? Function(String aId, String bId) similarity,
    {int pool = 6}) {
  final top = rankForDisplay(candidates).take(pool).toList();
  if (top.length < 2) return null;
  final scored = <(double, Candidate, Candidate, double?)>[];
  for (var i = 0; i < top.length; i++) {
    for (var j = i + 1; j < top.length; j++) {
      final a = top[i];
      final b = top[j];
      final sim = similarity(a.entity.id, b.entity.id) ?? similarity(b.entity.id, a.entity.id);
      final distinct = 1 - (sim ?? tagSimilarity(a.entity, b.entity));
      final base = (a.score + b.score) / 2;
      final aBecause = a.because.toSet();
      final bBecause = b.because.toSet();
      final diverse = aBecause.isNotEmpty && bBecause.isNotEmpty && !aBecause.containsAll(bBecause) ? 0.05 : 0.0;
      final sameCreator = a.entity.creator != null && a.entity.creator == b.entity.creator ? 0.15 : 0.0;
      final pairScore = base * (0.6 + 0.4 * distinct) + diverse - sameCreator;
      scored.add((pairScore, a, b, sim));
    }
  }
  scored.sort((x, y) => y.$1.compareTo(x.$1));
  final best = scored.first;
  // Show the stronger comp first so the line reads naturally.
  final first = best.$2.score >= best.$3.score ? best.$2 : best.$3;
  final second = identical(first, best.$2) ? best.$3 : best.$2;
  return CompPairing(
    a: first,
    b: second,
    similarity: best.$4,
    score: best.$1,
    alternatives: scored.skip(1).take(3).map((s) => [s.$2.entity.id, s.$3.entity.id]).toList(),
  );
}

/// Jaccard overlap of descriptive tags; a fallback similarity.
double tagSimilarity(Entity a, Entity b) {
  bool descriptive(TagRef t) => const {'genre', 'subgenre', 'keyword', 'style', 'theme', 'category'}.contains(t.family);
  final ta = a.tags.where(descriptive).map((t) => t.id).toSet();
  final tb = b.tags.where(descriptive).map((t) => t.id).toSet();
  if (ta.isEmpty || tb.isEmpty) return 0.5;
  final inter = ta.intersection(tb).length;
  final union = ta.union(tb).length;
  return union == 0 ? 0.5 : inter / union;
}

/// A heatmap cell from Qloo (`urn:heatmap`).
class HeatCell {
  const HeatCell({required this.lat, required this.lon, required this.affinity, required this.affinityRank, required this.popularity});

  final double lat;
  final double lon;
  final double affinity;
  final double affinityRank;
  final double popularity;
}

double haversineKm(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLon = rad(lon2 - lon1);
  final h = math.pow(math.sin(dLat / 2), 2) + math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLon / 2), 2);
  return 2 * r * math.asin(math.sqrt(h.toDouble()));
}

/// Rolls heatmap cells up into named cities and labels each one.
///
/// Raw heatmap affinity tracks population, so big cities crowd the top. We
/// keep that ranking (it is where the audience is) and add "hidden gems":
/// cities where fan affinity runs well ahead of general popularity.
List<MarketCity> aggregateMarkets(List<HeatCell> cells, List<City> cities, {double radiusKm = 60, int take = 8}) {
  final buckets = <City, List<HeatCell>>{};
  for (final cell in cells) {
    City? best;
    var bestKm = double.infinity;
    for (final city in cities) {
      // Cheap box check before the trig.
      if ((city.lat - cell.lat).abs() > 1.2 || (city.lon - cell.lon).abs() > 1.8) continue;
      final km = haversineKm(cell.lat, cell.lon, city.lat, city.lon);
      if (km < bestKm) {
        bestKm = km;
        best = city;
      }
    }
    if (best != null && bestKm <= radiusKm) (buckets[best] ??= []).add(cell);
  }
  final raw = <(City, double, double, int)>[];
  buckets.forEach((city, list) {
    final aff = list.map((c) => c.affinityRank > 0 ? c.affinityRank : c.affinity).reduce(math.max);
    final pop = list.map((c) => c.popularity).reduce((a, b) => a + b) / list.length;
    raw.add((city, aff, pop, list.length));
  });
  // Hidden gems: fans clearly ahead of the general market. Keep only the
  // three biggest gaps so the label stays meaningful.
  final gemCities = (raw.where((r) => r.$2 - r.$3 >= 0.15 && r.$2 >= 0.85).toList()
        ..sort((a, b) => (b.$2 - b.$3).compareTo(a.$2 - a.$3)))
      .take(3)
      .map((r) => r.$1)
      .toSet();
  final markets = [
    for (final (city, aff, pop, n) in raw)
      MarketCity(
        name: city.name,
        country: city.country,
        lat: city.lat,
        lon: city.lon,
        affinity: aff,
        popularity: pop,
        cells: n,
        label: gemCities.contains(city) ? 'hidden_gem' : (aff >= 0.97 ? 'stronghold' : 'emerging'),
      ),
  ]..sort((a, b) => b.affinity.compareTo(a.affinity));
  final top = markets.take(take - 2).toList();
  final gems = markets.where((m) => m.label == 'hidden_gem' && !top.contains(m)).toList()
    ..sort((a, b) => b.lift.compareTo(a.lift));
  return [...top, ...gems.take(2), ...markets.where((m) => !top.contains(m) && !gems.take(2).contains(m))]
      .take(take)
      .toList();
}

/// "Your readers skew 25–34 and lean female." style summary.
String describeAudience(AudienceProfile profile, String noun) {
  final parts = <String>[];
  final ages = profile.coreAges;
  if (ages.isNotEmpty) {
    final sorted = [...ages.take(2)]..sort((a, b) => a.index.compareTo(b.index));
    final label = sorted.length == 2 && sorted[1].index == sorted[0].index + 1
        ? '${sorted[0].label.split('–').first}–${sorted[1].label.split('–').last}'
        : sorted.map((a) => a.label).join(' and ');
    parts.add('skew $label');
  }
  final lean = profile.genderLean;
  if (lean != null) parts.add('lean $lean');
  if (parts.isEmpty) return 'Your $noun are broadly spread across ages and genders.';
  return 'Your $noun ${parts.join(' and ')}.';
}

/// Human labels for candidate flags.
String flagLabel(String flag) => switch (flag) {
      'too_big' => 'Too big to comp',
      'too_small' => 'Very small',
      'dated' => 'Outside your window',
      'weak_fit' => 'Weaker fit',
      _ => flag,
    };

/// Readable "Top 0.4%" text.
String topPercentLabel(double? popularity) {
  if (popularity == null) return 'Size unknown';
  final top = (1 - popularity) * 100;
  if (top < 0.01) return 'Top 0.01%';
  if (top < 1) {
    final text = top.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    return 'Top $text%';
  }
  return 'Top ${top.round()}%';
}

extension EntityKindPrimary on EntityKind {
  /// Whether Qloo exposes a year-based filter for this category.
  bool get hasYear => this == EntityKind.book || this == EntityKind.movie || this == EntityKind.tvShow;
}
