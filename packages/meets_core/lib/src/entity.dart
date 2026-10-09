import 'json.dart';
import 'kinds.dart';

/// A Qloo tag (genre, keyword, audience descriptor ...).
class TagRef {
  const TagRef({required this.id, required this.name, this.type, this.score});

  final String id;
  final String name;

  /// Tag family URN, e.g. `urn:tag:genre:media`.
  final String? type;

  /// Affinity or relevance when the tag came from a taste analysis.
  final double? score;

  /// `urn:tag:genre:media:fantasy` -> `genre`.
  String get family {
    final source = type ?? id;
    final parts = source.split(':');
    return parts.length > 2 ? parts[2] : '';
  }

  Json toJson() => compact({'id': id, 'name': name, 'type': type, 'score': score});

  factory TagRef.fromJson(Json json) => TagRef(
        id: asString(json['id']) ?? '',
        name: asString(json['name']) ?? '',
        type: asString(json['type']),
        score: asDouble(json['score']),
      );
}

/// One input entity that pulled a result up, from Qloo explainability.
class Driver {
  const Driver({required this.entityId, required this.score});

  final String entityId;
  final double score;

  Json toJson() => {'entityId': entityId, 'score': score};

  factory Driver.fromJson(Json json) =>
      Driver(entityId: asString(json['entityId']) ?? '', score: asDouble(json['score']) ?? 0);
}

/// A Qloo entity, reduced to what Meets shows and reasons about.
///
/// Every number here is passed through from Qloo (or null). Meets never
/// invents an affinity or popularity value.
class Entity {
  const Entity({
    required this.id,
    required this.name,
    required this.kind,
    this.year,
    this.creator,
    this.description,
    this.imageUrl,
    this.popularity,
    this.affinity,
    this.tags = const [],
    this.drivers = const [],
    this.disambiguation,
  });

  final String id;
  final String name;
  final EntityKind kind;
  final int? year;

  /// Author, artist, studio or network when Qloo provides one.
  final String? creator;
  final String? description;
  final String? imageUrl;

  /// Qloo popularity percentile (0..1) across all entities of the type.
  final double? popularity;

  /// Qloo affinity (0..1) for the request that returned this entity.
  final double? affinity;
  final List<TagRef> tags;
  final List<Driver> drivers;
  final String? disambiguation;

  /// "Top 0.4%" style size, derived from popularity.
  double? get topPercent => popularity == null ? null : ((1 - popularity!) * 100).clamp(0, 100).toDouble();

  Entity copyWith({double? affinity, List<Driver>? drivers, String? imageUrl}) => Entity(
        id: id,
        name: name,
        kind: kind,
        year: year,
        creator: creator,
        description: description,
        imageUrl: imageUrl ?? this.imageUrl,
        popularity: popularity,
        affinity: affinity ?? this.affinity,
        tags: tags,
        drivers: drivers ?? this.drivers,
        disambiguation: disambiguation,
      );

  Json toJson() => compact({
        'id': id,
        'name': name,
        'kind': kind.name,
        'year': year,
        'creator': creator,
        'description': description,
        'imageUrl': imageUrl,
        'popularity': popularity,
        'affinity': affinity,
        'tags': tags.map((t) => t.toJson()).toList(),
        'drivers': drivers.map((d) => d.toJson()).toList(),
        'disambiguation': disambiguation,
      });

  factory Entity.fromJson(Json json) => Entity(
        id: asString(json['id']) ?? '',
        name: asString(json['name']) ?? '',
        kind: EntityKind.fromName(asString(json['kind'])),
        year: asInt(json['year']),
        creator: asString(json['creator']),
        description: asString(json['description']),
        imageUrl: asString(json['imageUrl']),
        popularity: asDouble(json['popularity']),
        affinity: asDouble(json['affinity']),
        tags: listOf(json['tags'], TagRef.fromJson),
        drivers: listOf(json['drivers'], Driver.fromJson),
        disambiguation: asString(json['disambiguation']),
      );

  @override
  String toString() => 'Entity($name, ${kind.name}, $id)';
}
