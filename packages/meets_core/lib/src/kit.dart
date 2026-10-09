import 'brief.dart';
import 'entity.dart';
import 'json.dart';
import 'kinds.dart';
import 'scoring.dart';

/// A ranked result inside a scan, with Meets' reading of the Qloo numbers.
class Candidate {
  const Candidate({
    required this.entity,
    required this.fit,
    required this.size,
    this.recency,
    required this.score,
    this.flags = const [],
    this.because = const [],
    this.rank = 0,
  });

  final Entity entity;

  /// 0..1. Position in Qloo's affinity-ranked list blended with the affinity
  /// value, so it is comparable across scans.
  final double fit;
  final SizeBand size;
  final RecencyBand? recency;

  /// 0..1 "sweet spot" score: fit, adjusted for size and recency preferences.
  final double score;

  /// Plain-language warnings: `too_big`, `too_small`, `dated`, `weak_fit`.
  final List<String> flags;

  /// Names of the creator's touchstones that drove this pick (explainability).
  final List<String> because;

  /// 1-based position in Qloo's response.
  final int rank;

  bool get isSweetSpot => flags.isEmpty && fit >= 0.5;

  Json toJson() => compact({
        'entity': entity.toJson(),
        'fit': fit,
        'size': size.name,
        'recency': recency?.name,
        'score': score,
        'flags': flags,
        'because': because,
        'rank': rank,
      });

  factory Candidate.fromJson(Json json) => Candidate(
        entity: Entity.fromJson(asJson(json['entity'])),
        fit: asDouble(json['fit']) ?? 0,
        size: SizeBand.fromName(asString(json['size'])),
        recency: RecencyBand.fromName(asString(json['recency'])),
        score: asDouble(json['score']) ?? 0,
        flags: stringsOf(json['flags']),
        because: stringsOf(json['because']),
        rank: asInt(json['rank']) ?? 0,
      );
}

/// One Qloo category scanned for this brief.
class DomainScan {
  const DomainScan({
    required this.kind,
    required this.role,
    required this.items,
    this.filters = const [],
    this.notes = const [],
  });

  final EntityKind kind;

  /// `primary`, `cross` or `channel`.
  final String role;
  final List<Candidate> items;

  /// Human-readable filters that were applied ("Published 2021 or later").
  final List<String> filters;

  /// What the agent changed and why ("Only 4 matches; dropped the genre filter").
  final List<String> notes;

  Json toJson() => compact({
        'kind': kind.name,
        'role': role,
        'items': items.map((c) => c.toJson()).toList(),
        'filters': filters,
        'notes': notes,
      });

  factory DomainScan.fromJson(Json json) => DomainScan(
        kind: EntityKind.fromName(asString(json['kind'])),
        role: asString(json['role']) ?? 'cross',
        items: listOf(json['items'], Candidate.fromJson),
        filters: stringsOf(json['filters']),
        notes: stringsOf(json['notes']),
      );
}

/// The "A meets B" pairing chosen for the comp line.
class CompPairing {
  const CompPairing({
    required this.a,
    required this.b,
    this.similarity,
    this.score = 0,
    this.alternatives = const [],
    this.why,
  });

  final Candidate a;
  final Candidate b;

  /// Qloo affinity of B when A is the signal (how alike the two are). Lower
  /// means each comp brings something the other does not.
  final double? similarity;
  final double score;

  /// Runner-up pairs as [aId, bId] lists.
  final List<List<String>> alternatives;
  final String? why;

  String get line => '${a.entity.name} meets ${b.entity.name}';

  Json toJson() => compact({
        'a': a.toJson(),
        'b': b.toJson(),
        'similarity': similarity,
        'score': score,
        'alternatives': alternatives,
        'why': why,
      });

  factory CompPairing.fromJson(Json json) => CompPairing(
        a: Candidate.fromJson(asJson(json['a'])),
        b: Candidate.fromJson(asJson(json['b'])),
        similarity: asDouble(json['similarity']),
        score: asDouble(json['score']) ?? 0,
        alternatives: asList(json['alternatives']).map(stringsOf).toList(),
        why: asString(json['why']),
      );
}

/// Audience snapshot from Qloo demographics and taste analysis.
class AudienceProfile {
  const AudienceProfile({this.age = const {}, this.male, this.female, this.descriptors = const []});

  /// Age band -> relative affinity (-1..1; positive means over-indexes).
  final Map<AgeBand, double> age;
  final double? male;
  final double? female;

  /// Tags that describe the audience's taste, strongest first.
  final List<TagRef> descriptors;

  bool get isEmpty => age.isEmpty && male == null && descriptors.isEmpty;

  /// Bands that over-index, strongest first.
  List<AgeBand> get coreAges {
    final entries = age.entries.where((e) => e.value > 0.05).toList()
      ..sort((x, y) => y.value.compareTo(x.value));
    return entries.map((e) => e.key).toList();
  }

  /// 'female', 'male' or null when the skew is small.
  String? get genderLean {
    if (male == null || female == null) return null;
    if ((female! - male!).abs() < 0.08) return null;
    return female! > male! ? 'female' : 'male';
  }

  Json toJson() => compact({
        'age': {for (final e in age.entries) e.key.key: e.value},
        'male': male,
        'female': female,
        'descriptors': descriptors.map((t) => t.toJson()).toList(),
      });

  factory AudienceProfile.fromJson(Json json) {
    final ageJson = asJson(json['age']);
    final age = <AgeBand, double>{};
    for (final band in AgeBand.values) {
      final v = asDouble(ageJson[band.key]);
      if (v != null) age[band] = v;
    }
    return AudienceProfile(
      age: age,
      male: asDouble(json['male']),
      female: asDouble(json['female']),
      descriptors: listOf(json['descriptors'], TagRef.fromJson),
    );
  }
}

/// A city where the audience over-indexes, aggregated from heatmap cells.
class MarketCity {
  const MarketCity({
    required this.name,
    required this.country,
    required this.lat,
    required this.lon,
    required this.affinity,
    required this.popularity,
    required this.cells,
    required this.label,
  });

  final String name;
  final String country;
  final double lat;
  final double lon;

  /// Best heatmap affinity rank (0..1) among the city's cells.
  final double affinity;

  /// Mean popularity of the city's cells (0..1) - how busy the market is.
  final double popularity;
  final int cells;

  /// `stronghold`, `hidden_gem`, `emerging`.
  final String label;

  double get lift => affinity - popularity;

  Json toJson() => {
        'name': name,
        'country': country,
        'lat': lat,
        'lon': lon,
        'affinity': affinity,
        'popularity': popularity,
        'cells': cells,
        'label': label,
      };

  factory MarketCity.fromJson(Json json) => MarketCity(
        name: asString(json['name']) ?? '',
        country: asString(json['country']) ?? '',
        lat: asDouble(json['lat']) ?? 0,
        lon: asDouble(json['lon']) ?? 0,
        affinity: asDouble(json['affinity']) ?? 0,
        popularity: asDouble(json['popularity']) ?? 0,
        cells: asInt(json['cells']) ?? 0,
        label: asString(json['label']) ?? 'emerging',
      );
}

/// Meets' verdict on a comp the creator already planned to use.
class CompVerdict {
  const CompVerdict({
    required this.input,
    this.resolved,
    this.fit,
    this.size,
    this.recency,
    required this.verdict,
    this.reasons = const [],
    this.swap,
  });

  final String input;
  final Entity? resolved;
  final double? fit;
  final SizeBand? size;
  final RecencyBand? recency;

  /// `keep`, `swap` or `not_found`.
  final String verdict;
  final List<String> reasons;
  final Candidate? swap;

  Json toJson() => compact({
        'input': input,
        'resolved': resolved?.toJson(),
        'fit': fit,
        'size': size?.name,
        'recency': recency?.name,
        'verdict': verdict,
        'reasons': reasons,
        'swap': swap?.toJson(),
      });

  factory CompVerdict.fromJson(Json json) => CompVerdict(
        input: asString(json['input']) ?? '',
        resolved: json['resolved'] == null ? null : Entity.fromJson(asJson(json['resolved'])),
        fit: asDouble(json['fit']),
        size: json['size'] == null ? null : SizeBand.fromName(asString(json['size'])),
        recency: RecencyBand.fromName(asString(json['recency'])),
        verdict: asString(json['verdict']) ?? 'not_found',
        reasons: stringsOf(json['reasons']),
        swap: json['swap'] == null ? null : Candidate.fromJson(asJson(json['swap'])),
      );
}

/// A piece of pitch copy. [body] may contain `{{id}}` entity references that
/// the server has already resolved to names.
class CopyBlock {
  const CopyBlock({required this.id, required this.title, required this.body, this.hint = '', this.author = 'template'});

  final String id;
  final String title;
  final String body;
  final String hint;

  /// `llm` or `template`, so the UI can be honest about who wrote it.
  final String author;

  Json toJson() => {'id': id, 'title': title, 'body': body, 'hint': hint, 'author': author};

  factory CopyBlock.fromJson(Json json) => CopyBlock(
        id: asString(json['id']) ?? '',
        title: asString(json['title']) ?? '',
        body: asString(json['body']) ?? '',
        hint: asString(json['hint']) ?? '',
        author: asString(json['author']) ?? 'template',
      );
}

/// A ready-to-paste targeting list.
class TargetList {
  const TargetList({required this.id, required this.platform, required this.how, required this.items});

  final String id;
  final String platform;
  final String how;
  final List<String> items;

  Json toJson() => {'id': id, 'platform': platform, 'how': how, 'items': items};

  factory TargetList.fromJson(Json json) => TargetList(
        id: asString(json['id']) ?? '',
        platform: asString(json['platform']) ?? '',
        how: asString(json['how']) ?? '',
        items: stringsOf(json['items']),
      );
}

/// What a plain language model suggests, checked against Qloo.
class BaselineItem {
  const BaselineItem({required this.name, this.resolved, this.fit, this.size, this.recency, required this.verdict});

  final String name;
  final Entity? resolved;
  final double? fit;
  final SizeBand? size;
  final RecencyBand? recency;

  /// `strong`, `too_big`, `dated`, `weak_fit`, `not_found`.
  final String verdict;

  Json toJson() => compact({
        'name': name,
        'resolved': resolved?.toJson(),
        'fit': fit,
        'size': size?.name,
        'recency': recency?.name,
        'verdict': verdict,
      });

  factory BaselineItem.fromJson(Json json) => BaselineItem(
        name: asString(json['name']) ?? '',
        resolved: json['resolved'] == null ? null : Entity.fromJson(asJson(json['resolved'])),
        fit: asDouble(json['fit']),
        size: json['size'] == null ? null : SizeBand.fromName(asString(json['size'])),
        recency: RecencyBand.fromName(asString(json['recency'])),
        verdict: asString(json['verdict']) ?? 'not_found',
      );
}

class BaselineResult {
  const BaselineResult({required this.model, required this.items, required this.summary});

  final String model;
  final List<BaselineItem> items;
  final String summary;

  Json toJson() => {'model': model, 'items': items.map((i) => i.toJson()).toList(), 'summary': summary};

  factory BaselineResult.fromJson(Json json) => BaselineResult(
        model: asString(json['model']) ?? '',
        items: listOf(json['items'], BaselineItem.fromJson),
        summary: asString(json['summary']) ?? '',
      );
}

/// Counters that make the run auditable.
class KitStats {
  const KitStats({this.qlooCalls = 0, this.cachedCalls = 0, this.llmCalls = 0, this.durationMs = 0, this.model});

  final int qlooCalls;
  final int cachedCalls;
  final int llmCalls;
  final int durationMs;
  final String? model;

  Json toJson() => compact({
        'qlooCalls': qlooCalls,
        'cachedCalls': cachedCalls,
        'llmCalls': llmCalls,
        'durationMs': durationMs,
        'model': model,
      });

  factory KitStats.fromJson(Json json) => KitStats(
        qlooCalls: asInt(json['qlooCalls']) ?? 0,
        cachedCalls: asInt(json['cachedCalls']) ?? 0,
        llmCalls: asInt(json['llmCalls']) ?? 0,
        durationMs: asInt(json['durationMs']) ?? 0,
        model: asString(json['model']),
      );
}

/// Everything Meets produces for one brief: the "Comp Kit".
class CompKit {
  const CompKit({
    required this.id,
    required this.createdAt,
    required this.brief,
    required this.mode,
    this.version = 1,
    this.anchors = const [],
    this.themes = const [],
    required this.primary,
    this.cross = const [],
    this.channels = const [],
    this.pairing,
    this.audience,
    this.markets = const [],
    this.compCheck = const [],
    this.copy = const [],
    this.targeting = const [],
    this.baseline,
    this.headline,
    this.summary,
    this.notes = const [],
    this.stats = const KitStats(),
  });

  final String id;
  final DateTime createdAt;
  final Brief brief;

  /// `live` (real Qloo) or `preview` (labelled sample data for UI work).
  final String mode;
  final int version;

  /// The creator's touchstones as Qloo resolved them.
  final List<Entity> anchors;

  /// Themes resolved to Qloo tags.
  final List<TagRef> themes;
  final DomainScan primary;
  final List<DomainScan> cross;
  final List<DomainScan> channels;
  final CompPairing? pairing;
  final AudienceProfile? audience;
  final List<MarketCity> markets;
  final List<CompVerdict> compCheck;
  final List<CopyBlock> copy;
  final List<TargetList> targeting;
  final BaselineResult? baseline;

  /// One sentence that frames the kit.
  final String? headline;

  /// Short strategy summary.
  final String? summary;

  /// Honest limits and agent decisions worth surfacing.
  final List<String> notes;
  final KitStats stats;

  /// Every entity in the kit, by id. Used for grounding checks and images.
  Map<String, Entity> get ledger {
    final out = <String, Entity>{};
    void add(Entity? e) {
      if (e != null && e.id.isNotEmpty) out[e.id] = e;
    }

    anchors.forEach(add);
    for (final scan in [primary, ...cross, ...channels]) {
      for (final c in scan.items) {
        add(c.entity);
      }
    }
    for (final v in compCheck) {
      add(v.resolved);
      add(v.swap?.entity);
    }
    for (final b in baseline?.items ?? const <BaselineItem>[]) {
      add(b.resolved);
    }
    return out;
  }

  CompKit copyWith({
    int? version,
    List<CopyBlock>? copy,
    BaselineResult? baseline,
    String? headline,
    String? summary,
    List<String>? notes,
    KitStats? stats,
    CompPairing? pairing,
  }) =>
      CompKit(
        id: id,
        createdAt: createdAt,
        brief: brief,
        mode: mode,
        version: version ?? this.version,
        anchors: anchors,
        themes: themes,
        primary: primary,
        cross: cross,
        channels: channels,
        pairing: pairing ?? this.pairing,
        audience: audience,
        markets: markets,
        compCheck: compCheck,
        copy: copy ?? this.copy,
        targeting: targeting,
        baseline: baseline ?? this.baseline,
        headline: headline ?? this.headline,
        summary: summary ?? this.summary,
        notes: notes ?? this.notes,
        stats: stats ?? this.stats,
      );

  Json toJson() => compact({
        'id': id,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'brief': brief.toJson(),
        'mode': mode,
        'version': version,
        'anchors': anchors.map((e) => e.toJson()).toList(),
        'themes': themes.map((t) => t.toJson()).toList(),
        'primary': primary.toJson(),
        'cross': cross.map((s) => s.toJson()).toList(),
        'channels': channels.map((s) => s.toJson()).toList(),
        'pairing': pairing?.toJson(),
        'audience': audience?.toJson(),
        'markets': markets.map((m) => m.toJson()).toList(),
        'compCheck': compCheck.map((v) => v.toJson()).toList(),
        'copy': copy.map((c) => c.toJson()).toList(),
        'targeting': targeting.map((t) => t.toJson()).toList(),
        'baseline': baseline?.toJson(),
        'headline': headline,
        'summary': summary,
        'notes': notes,
        'stats': stats.toJson(),
      });

  factory CompKit.fromJson(Json json) => CompKit(
        id: asString(json['id']) ?? '',
        createdAt: DateTime.tryParse(asString(json['createdAt']) ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
        brief: Brief.fromJson(asJson(json['brief'])),
        mode: asString(json['mode']) ?? 'live',
        version: asInt(json['version']) ?? 1,
        anchors: listOf(json['anchors'], Entity.fromJson),
        themes: listOf(json['themes'], TagRef.fromJson),
        primary: DomainScan.fromJson(asJson(json['primary'])),
        cross: listOf(json['cross'], DomainScan.fromJson),
        channels: listOf(json['channels'], DomainScan.fromJson),
        pairing: json['pairing'] == null ? null : CompPairing.fromJson(asJson(json['pairing'])),
        audience: json['audience'] == null ? null : AudienceProfile.fromJson(asJson(json['audience'])),
        markets: listOf(json['markets'], MarketCity.fromJson),
        compCheck: listOf(json['compCheck'], CompVerdict.fromJson),
        copy: listOf(json['copy'], CopyBlock.fromJson),
        targeting: listOf(json['targeting'], TargetList.fromJson),
        baseline: json['baseline'] == null ? null : BaselineResult.fromJson(asJson(json['baseline'])),
        headline: asString(json['headline']),
        summary: asString(json['summary']),
        notes: stringsOf(json['notes']),
        stats: KitStats.fromJson(asJson(json['stats'])),
      );
}
