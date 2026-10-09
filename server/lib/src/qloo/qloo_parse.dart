import 'package:meets_core/meets_core.dart';

/// Turns Qloo JSON into Meets models. Defensive on purpose: entity
/// `properties` vary by category and several fields are undocumented, so
/// every read tolerates absence and alternate spellings.

const _descriptiveFamilies = {
  'genre',
  'subgenre',
  'keyword',
  'style',
  'theme',
  'category',
  'audience',
  'emotional_tone',
  'critical_descriptor',
  'aesthetic_property',
  'lifestyle',
  'plot',
  'setting',
  'mood',
};

const _noisyFamilies = {
  'streaming_service',
  'payments',
  'accessibility',
  'service_type',
  'offerings',
  'amenity',
  'parking',
  'children',
  'crowd',
  'planning',
  'dining_options',
  'highlights',
};

TagRef? parseTag(Object? raw) {
  final json = asJson(raw);
  final id = asString(json['id']) ?? asString(json['tag_id']) ?? asString(json['tag_value']);
  final name = asString(json['name']);
  if (id == null || name == null) return null;
  final query = asJson(json['query']);
  return TagRef(
    id: id,
    name: _cleanName(name),
    type: asString(json['subtype']) ?? asString(json['type']),
    score: asDouble(query['affinity']) ?? asDouble(json['affinity']) ?? asDouble(json['score']) ?? asDouble(json['weight']),
  );
}

String _cleanName(String s) {
  final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.isEmpty) return t;
  return t[0].toUpperCase() + t.substring(1);
}

bool isDescriptiveTag(TagRef tag) {
  final family = tag.family;
  if (_noisyFamilies.contains(family)) return false;
  return _descriptiveFamilies.contains(family) || family.isEmpty;
}

EntityKind _kindOf(Json raw) {
  for (final candidate in [raw['subtype'], ...asList(raw['types']), raw['type']]) {
    final s = asString(candidate);
    if (s != null && s.startsWith('urn:entity:')) {
      final kind = EntityKind.fromUrn(s);
      if (kind != EntityKind.unknown) return kind;
    }
  }
  return EntityKind.unknown;
}

int? _yearOf(Json props) {
  for (final key in ['release_year', 'publication_year', 'first_publication_year', 'year', 'start_year']) {
    final y = asInt(props[key]);
    if (y != null && y > 1000 && y < 3000) return y;
  }
  for (final key in ['release_date', 'publication_date', 'first_air_date', 'date']) {
    final s = asString(props[key]);
    final y = s == null ? null : int.tryParse(s.split('-').first);
    if (y != null && y > 1000 && y < 3000) return y;
  }
  return null;
}

String? _nameish(Object? value) {
  if (value is String) return value.trim().isEmpty ? null : value.trim();
  if (value is Map) return asString(value['name']);
  if (value is List && value.isNotEmpty) {
    final names = value.map(_nameish).whereType<String>().take(2).toList();
    return names.isEmpty ? null : names.join(' & ');
  }
  return null;
}

String? _creatorOf(Json props) {
  for (final key in ['author', 'authors', 'artist', 'artists', 'creator', 'creators', 'developer', 'developers', 'director', 'directors', 'host', 'hosts']) {
    final name = _nameish(props[key]);
    if (name != null) return name;
  }
  return null;
}

String? _english(Object? values) {
  for (final item in asList(values)) {
    final json = asJson(item);
    final langs = stringsOf(json['languages']);
    if ((langs.isEmpty || langs.contains('en')) && asString(json['value']) != null) return asString(json['value']);
  }
  return null;
}

String? _descriptionOf(Json props) {
  final text = asString(props['description']) ?? asString(props['short_description']) ?? _english(props['short_descriptions']);
  if (text == null) return null;
  final t = text.trim();
  return t.length > 420 ? '${t.substring(0, 417).trimRight()}…' : t;
}

String? _imageOf(Json props) {
  final image = props['image'];
  if (image is Map) {
    final url = asString(image['url']);
    if (url != null) return url;
  } else if (image is String && image.startsWith('http')) {
    return image;
  }
  for (final item in asList(props['images'])) {
    final url = asString(asJson(item)['url']);
    if (url != null) return url;
  }
  return null;
}

List<Driver> _driversOf(Json query) {
  final out = <Driver>[];
  final explain = query['explainability'];
  if (explain is Map) {
    explain.forEach((key, value) {
      if (value is num && key is String && !key.startsWith('signal.')) {
        out.add(Driver(entityId: key, score: value.toDouble()));
      } else if (value is List) {
        for (final item in value) {
          final json = asJson(item);
          final id = asString(json['entity_id']) ?? asString(json['tag_id']) ?? asString(json['id']);
          final score = asDouble(json['score']);
          if (id != null && score != null) out.add(Driver(entityId: id, score: score));
        }
      }
    });
  }
  out.sort((a, b) => b.score.compareTo(a.score));
  return out;
}

/// One Qloo entity (from search, insights or entities lookup).
Entity? parseEntity(Object? raw, {int maxTags = 12}) {
  final json = asJson(raw);
  final id = asString(json['entity_id']) ?? asString(json['id']);
  final name = asString(json['name']);
  if (id == null || name == null) return null;
  final props = asJson(json['properties']);
  final query = asJson(json['query']);
  final tags = asList(json['tags'])
      .map(parseTag)
      .whereType<TagRef>()
      .where(isDescriptiveTag)
      .fold<List<TagRef>>([], (list, t) => list.any((x) => x.name.toLowerCase() == t.name.toLowerCase()) ? list : (list..add(t)))
      .take(maxTags)
      .toList();
  return Entity(
    id: id,
    name: name.trim(),
    kind: _kindOf(json),
    year: _yearOf(props),
    creator: _creatorOf(props),
    description: _descriptionOf(props),
    imageUrl: _imageOf(props),
    popularity: asDouble(json['popularity']) ?? asDouble(props['popularity']),
    affinity: asDouble(query['affinity']) ?? asDouble(json['affinity']),
    tags: tags,
    drivers: _driversOf(query),
    disambiguation: asString(json['disambiguation']) ?? asString(props['disambiguation']),
  );
}

List<Entity> _entitiesIn(Object? results) {
  if (results is List) return results.map((e) => parseEntity(e)).whereType<Entity>().toList();
  final json = asJson(results);
  return asList(json['entities']).map((e) => parseEntity(e)).whereType<Entity>().toList();
}

/// `/search` responses put entities in `results` (a list).
List<Entity> parseSearch(Json response) => _entitiesIn(response['results']);

/// `/v2/insights` entity responses put them in `results.entities`.
List<Entity> parseInsightsEntities(Json response) => _entitiesIn(response['results']);

/// `/entities` lookup.
List<Entity> parseEntities(Json response) => _entitiesIn(response['results'] ?? response['entities']);

/// `/v2/tags` and `urn:tag` insights.
List<TagRef> parseTags(Json response) {
  final results = response['results'];
  final list = results is List ? results : asList(asJson(results)['tags']);
  return list.map(parseTag).whereType<TagRef>().toList();
}

/// `urn:demographics` insights. When several signals are sent Qloo returns one
/// block per signal; we average them into one profile.
AudienceProfile? parseDemographics(Json response) {
  final blocks = asList(asJson(response['results'])['demographics']);
  if (blocks.isEmpty) return null;
  final sums = <AgeBand, double>{};
  final counts = <AgeBand, int>{};
  double male = 0, female = 0;
  var genderCount = 0;
  for (final block in blocks) {
    final query = asJson(asJson(block)['query']);
    final age = asJson(query['age']);
    for (final band in AgeBand.values) {
      final v = asDouble(age[band.key]);
      if (v != null) {
        sums[band] = (sums[band] ?? 0) + v;
        counts[band] = (counts[band] ?? 0) + 1;
      }
    }
    final gender = asJson(query['gender']);
    final m = asDouble(gender['male']);
    final f = asDouble(gender['female']);
    if (m != null && f != null) {
      male += m;
      female += f;
      genderCount++;
    }
  }
  return AudienceProfile(
    age: {for (final band in sums.keys) band: sums[band]! / counts[band]!},
    male: genderCount == 0 ? null : male / genderCount,
    female: genderCount == 0 ? null : female / genderCount,
  );
}

/// `urn:heatmap` insights.
List<HeatCell> parseHeatmap(Json response) {
  final points = asList(asJson(response['results'])['heatmap']);
  final out = <HeatCell>[];
  for (final point in points) {
    final json = asJson(point);
    final loc = asJson(json['location']);
    final query = asJson(json['query']);
    final lat = asDouble(loc['latitude']) ?? asDouble(loc['lat']);
    final lon = asDouble(loc['longitude']) ?? asDouble(loc['lon']) ?? asDouble(loc['lng']);
    if (lat == null || lon == null) continue;
    out.add(HeatCell(
      lat: lat,
      lon: lon,
      affinity: asDouble(query['affinity']) ?? 0,
      affinityRank: asDouble(query['affinity_rank']) ?? 0,
      popularity: asDouble(query['popularity']) ?? 0,
    ));
  }
  return out;
}

/// `/v2/analysis/compare`. The response shape is not documented, so we look
/// for tag-like objects anywhere under `results` and keep their scores.
List<TagRef> parseCompare(Json response) {
  final found = <TagRef>[];
  void walk(Object? node, int depth) {
    if (depth > 4 || found.length > 60) return;
    if (node is List) {
      for (final item in node) {
        final tag = parseTag(item);
        if (tag != null && tag.id.startsWith('urn:tag')) {
          found.add(tag);
        } else {
          walk(item, depth + 1);
        }
      }
    } else if (node is Map) {
      for (final value in node.values) {
        walk(value, depth + 1);
      }
    }
  }

  walk(response['results'] ?? response, 0);
  final seen = <String>{};
  return found.where((t) => seen.add(t.id) && isDescriptiveTag(t)).toList();
}
