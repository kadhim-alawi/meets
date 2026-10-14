import 'package:meets_core/meets_core.dart';

import '../qloo/qloo_client.dart';
import '../qloo/qloo_parse.dart';
import 'emitter.dart';

/// Typed Qloo operations the agent uses. Every call is reported to the
/// [Emitter] with a human label, so the timeline reads like a lab notebook.
class QlooService {
  QlooService(this.client, this.emitter);

  final QlooClient client;
  final Emitter emitter;

  Future<Json> _get(String label, String path, Map<String, Object?> params, int Function(Json) count) async {
    QlooCall? record;
    final json = await client.get(path, params, onCall: (c) => record = c);
    emitter.qloo(record!, label: label, count: count(json));
    return json;
  }

  Future<Never> _fail(String label, QlooException e) async {
    emitter.emit('qloo', label,
        detail: e.message, data: {'path': e.path, 'status': e.status ?? 0, 'error': true});
    throw e;
  }

  /// `GET /search` - resolve a name to entities.
  Future<List<Entity>> search(String query, {List<EntityKind> kinds = const [], int take = 6, String? label}) async {
    final l = label ?? 'Searched Qloo for "$query"';
    try {
      final json = await _get(l, '/search', {
        'query': query,
        'types': kinds.where((k) => k != EntityKind.unknown).map((k) => k.urn).toList(),
        'take': take,
      }, (j) => parseSearch(j).length);
      return parseSearch(json);
    } on QlooException catch (e) {
      if (e.status == 404) {
        emitter.qloo(QlooCall(path: '/search', params: {'query': query}, status: 404, ms: 0, cached: false), label: l, count: 0);
        return const [];
      }
      return _fail(l, e);
    }
  }

  /// `GET /entities` - details for known ids.
  Future<List<Entity>> entities(List<String> ids, {String? label}) async {
    if (ids.isEmpty) return const [];
    final l = label ?? 'Loaded ${ids.length} entities';
    try {
      final json = await _get(l, '/entities', {'entity_ids': ids}, (j) => parseEntities(j).length);
      return parseEntities(json);
    } on QlooException catch (e) {
      return _fail(l, e);
    }
  }

  /// `GET /v2/tags` - find tag ids for a plain-language theme.
  Future<List<TagRef>> tags(String query, {EntityKind? parent, int take = 6, String? label}) async {
    final l = label ?? 'Looked up the theme "$query"';
    try {
      final json = await _get(l, '/v2/tags', {
        'filter.query': query,
        'filter.parents.types': parent?.urn,
        'take': take,
      }, (j) => parseTags(j).length);
      return parseTags(json);
    } on QlooException catch (e) {
      return _fail(l, e);
    }
  }

  /// `GET /v2/insights` returning entities.
  Future<List<Entity>> insights(Map<String, Object?> params, {required String label}) async {
    try {
      final json = await _get(label, '/v2/insights', params, (j) => parseInsightsEntities(j).length);
      return parseInsightsEntities(json);
    } on QlooException catch (e) {
      return _fail(label, e);
    }
  }

  /// Affinity of [candidateIds] to a signal, via `filter.results.entities`.
  Future<Map<String, double>> fitOf({
    required EntityKind kind,
    required List<String> signalIds,
    required List<String> candidateIds,
    required String label,
  }) async {
    if (candidateIds.isEmpty || signalIds.isEmpty) return const {};
    final list = await insights({
      'filter.type': kind.urn,
      'signal.interests.entities': signalIds,
      'filter.results.entities': candidateIds,
      'take': candidateIds.length.clamp(1, 50),
    }, label: label);
    return {for (final e in list) if (e.affinity != null) e.id: e.affinity!};
  }

  /// `urn:demographics` for a signal.
  Future<AudienceProfile?> demographics(List<String> signalIds, {required String label}) async {
    try {
      final json = await _get(label, '/v2/insights', {
        'filter.type': 'urn:demographics',
        'signal.interests.entities': signalIds,
      }, (j) => asList(asJson(j['results'])['demographics']).length);
      return parseDemographics(json);
    } on QlooException catch (e) {
      return _fail(label, e);
    }
  }

  /// `urn:tag` taste analysis for a signal.
  Future<List<TagRef>> tasteTags(List<String> signalIds,
      {EntityKind? parent, String? tagTypes, int take = 30, required String label}) async {
    try {
      final json = await _get(label, '/v2/insights', {
        'filter.type': 'urn:tag',
        'signal.interests.entities': signalIds,
        'filter.parents.types': parent?.urn,
        'filter.tag.types': tagTypes,
        'take': take,
      }, (j) => parseTags(j).length);
      return parseTags(json).where(isDescriptiveTag).toList();
    } on QlooException catch (e) {
      return _fail(label, e);
    }
  }

  /// `urn:heatmap` over a market.
  Future<List<HeatCell>> heatmap(List<String> signalIds, String locationQuery, {required String label}) async {
    try {
      final json = await _get(label, '/v2/insights', {
        'filter.type': 'urn:heatmap',
        'filter.location.query': locationQuery,
        'signal.interests.entities': signalIds,
      }, (j) => parseHeatmap(j).length);
      return parseHeatmap(json);
    } on QlooException catch (e) {
      return _fail(label, e);
    }
  }

  /// `GET /v2/analysis/compare` between two groups of entities.
  Future<List<TagRef>> compare(List<String> a, List<String> b, {required String label}) async {
    try {
      final json = await _get(label, '/v2/analysis/compare', {
        'a.signal.interests.entities': a,
        'b.signal.interests.entities': b,
      }, (j) => parseCompare(j).length);
      return parseCompare(json);
    } on QlooException catch (e) {
      return _fail(label, e);
    }
  }
}
