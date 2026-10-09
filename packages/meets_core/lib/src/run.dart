import 'json.dart';
import 'kit.dart';

/// What happened at one moment of an agent run. The app renders these as the
/// live timeline; the same list is kept with the kit as its audit trail.
class RunEvent {
  const RunEvent({
    required this.seq,
    required this.at,
    required this.kind,
    required this.title,
    this.detail,
    this.data = const {},
  });

  final int seq;
  final DateTime at;

  /// `step` (a stage starts), `qloo` (an API call), `decision` (the agent
  /// changed course), `llm`, `warn`, `done`, `error`.
  final String kind;
  final String title;
  final String? detail;

  /// Structured extras, e.g. `{path, params, count, ms, cached}` for `qloo`.
  final Json data;

  Json toJson() => compact({
        'seq': seq,
        'at': at.toUtc().toIso8601String(),
        'kind': kind,
        'title': title,
        'detail': detail,
        'data': data,
      });

  factory RunEvent.fromJson(Json json) => RunEvent(
        seq: asInt(json['seq']) ?? 0,
        at: DateTime.tryParse(asString(json['at']) ?? '') ?? DateTime.now(),
        kind: asString(json['kind']) ?? 'step',
        title: asString(json['title']) ?? '',
        detail: asString(json['detail']),
        data: asJson(json['data']),
      );
}

enum RunStatus {
  queued,
  running,
  done,
  failed;

  bool get finished => this == done || this == failed;

  static RunStatus fromName(String? name) =>
      values.firstWhere((v) => v.name == name, orElse: () => RunStatus.queued);
}

/// The polling view of a run: events since a cursor plus the kit when ready.
class RunSnapshot {
  const RunSnapshot({
    required this.id,
    required this.status,
    this.events = const [],
    this.kit,
    this.error,
    this.kitId,
  });

  final String id;
  final RunStatus status;
  final List<RunEvent> events;
  final CompKit? kit;
  final String? error;

  /// Id of the kit this run produces (refinements produce a new version of
  /// the same kit id).
  final String? kitId;

  Json toJson() => compact({
        'id': id,
        'status': status.name,
        'events': events.map((e) => e.toJson()).toList(),
        'kit': kit?.toJson(),
        'error': error,
        'kitId': kitId,
      });

  factory RunSnapshot.fromJson(Json json) => RunSnapshot(
        id: asString(json['id']) ?? '',
        status: RunStatus.fromName(asString(json['status'])),
        events: listOf(json['events'], RunEvent.fromJson),
        kit: json['kit'] == null ? null : CompKit.fromJson(asJson(json['kit'])),
        error: asString(json['error']),
        kitId: asString(json['kitId']),
      );
}
