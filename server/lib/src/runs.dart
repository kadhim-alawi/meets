import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:meets_core/meets_core.dart';
import 'package:path/path.dart' as p;

import 'agent/baseline.dart';
import 'agent/comps_agent.dart';
import 'agent/emitter.dart';
import 'agent/refine.dart';
import 'images.dart';
import 'llm/anthropic.dart';
import 'qloo/qloo_client.dart';

final _rand = Random.secure();
const _alphabet = 'abcdefghjkmnpqrstuvwxyz23456789';

String newId([int length = 10]) => List.generate(length, (_) => _alphabet[_rand.nextInt(_alphabet.length)]).join();

/// A request the server refuses for a reason the user can act on.
class LimitExceeded implements Exception {
  LimitExceeded(this.message);

  final String message;
}

class RunRecord {
  RunRecord({required this.id, required this.kitId, required this.kind, required this.ip}) : createdAt = DateTime.now();

  final String id;
  final String kitId;

  /// `build`, `refine` or `gutcheck`.
  final String kind;
  final String ip;
  final DateTime createdAt;
  RunStatus status = RunStatus.queued;
  final ListEmitter emitter = ListEmitter();
  CompKit? kit;
  String? error;

  RunSnapshot snapshot({int after = 0}) => RunSnapshot(
        id: id,
        status: status,
        events: emitter.events.where((e) => e.seq > after).toList(),
        kit: status == RunStatus.done ? kit : null,
        error: error,
        kitId: kitId,
      );
}

/// Finished kits with their audit trail, in memory and on disk.
class KitStore {
  KitStore({required this.dataDir, this.examplesDir, required this.images});

  final String dataDir;
  final String? examplesDir;
  final ImageProxy images;
  final _kits = <String, (CompKit, List<RunEvent>)>{};
  final _examples = <String>{};

  String get _dir => p.join(dataDir, 'kits');

  Future<void> load() async {
    for (final dir in [if (examplesDir != null) p.join(examplesDir!, 'kits'), _dir]) {
      final d = Directory(dir);
      if (!await d.exists()) continue;
      await for (final f in d.list()) {
        if (f is! File || !f.path.endsWith('.json')) continue;
        try {
          final json = asJson(jsonDecode(await f.readAsString()));
          final kit = CompKit.fromJson(asJson(json['kit']));
          final trace = listOf(json['trace'], RunEvent.fromJson);
          if (kit.id.isEmpty) continue;
          _kits[kit.id] = (kit, trace);
          if (dir != _dir) _examples.add(kit.id);
          _allowImages(kit);
        } on Object catch (e) {
          stderr.writeln('Skipping unreadable kit ${f.path}: $e');
        }
      }
    }
  }

  void _allowImages(CompKit kit) => images.allowAll(kit.ledger.values.map((e) => e.imageUrl));

  CompKit? get(String id) => _kits[id]?.$1;
  List<RunEvent> traceOf(String id) => _kits[id]?.$2 ?? const [];
  bool contains(String id) => _kits.containsKey(id);
  bool isExample(String id) => _examples.contains(id);

  Future<void> save(CompKit kit, List<RunEvent> trace) async {
    _kits[kit.id] = (kit, trace);
    _allowImages(kit);
    try {
      final file = File(p.join(_dir, '${kit.id}.json'));
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode({'kit': kit.toJson(), 'trace': trace.map((e) => e.toJson()).toList()}));
    } on Object catch (e) {
      stderr.writeln('Could not persist kit ${kit.id}: $e');
    }
  }
}

/// Starts agent runs in the background and serves their progress.
class RunManager {
  RunManager({
    required this.client,
    required this.llm,
    required this.kits,
    required this.images,
    this.runsPerHourPerIp = 20,
    this.runsPerDay = 400,
    this.maxConcurrent = 4,
  });

  final QlooClient client;
  final LlmClient? llm;
  final KitStore kits;
  final ImageProxy images;
  final int runsPerHourPerIp;
  final int runsPerDay;
  final int maxConcurrent;

  final _runs = <String, RunRecord>{};
  final _byIp = <String, Queue<DateTime>>{};
  final _day = Queue<DateTime>();
  int _active = 0;
  final _waiting = Queue<Completer<void>>();

  /// Kits with a refine or gut check in progress. One writer per kit, so
  /// concurrent updates can't overwrite each other.
  final _busyKits = <String>{};

  CompsAgent get agent => CompsAgent(client: client, llm: llm);

  RunRecord? run(String id) => _runs[id];

  void _checkLimits(String ip) {
    final now = DateTime.now();
    final hourAgo = now.subtract(const Duration(hours: 1));
    // Drop idle buckets so the map can't grow without bound.
    _byIp.removeWhere((_, q) {
      while (q.isNotEmpty && q.first.isBefore(hourAgo)) {
        q.removeFirst();
      }
      return q.isEmpty;
    });
    while (_day.isNotEmpty && now.difference(_day.first) > const Duration(days: 1)) {
      _day.removeFirst();
    }
    final q = _byIp.putIfAbsent(ip, Queue.new);
    if (q.length >= runsPerHourPerIp) {
      throw LimitExceeded('You have started $runsPerHourPerIp runs in the last hour. Try again a little later, or open one of the examples.');
    }
    if (_day.length >= runsPerDay) {
      throw LimitExceeded('Meets has hit its daily run budget for the shared Qloo key. Example kits still work.');
    }
    q.add(now);
    _day.add(now);
  }

  Future<void> _acquire() async {
    if (_active < maxConcurrent) {
      _active++;
      return;
    }
    final c = Completer<void>();
    _waiting.add(c);
    // The releasing run hands its slot over directly; _active is unchanged.
    await c.future;
  }

  void _release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeFirst().complete();
    } else {
      _active--;
    }
  }

  /// Counts a run against [ip]'s hourly and the server's daily budget.
  void reserve(String ip) => _checkLimits(ip);

  /// Runs [body] inside one of the concurrent-run slots.
  Future<T> withSlot<T>(Future<T> Function() body) async {
    await _acquire();
    try {
      return await body();
    } finally {
      _release();
    }
  }

  void _gc() {
    final cutoff = DateTime.now().subtract(const Duration(hours: 2));
    _runs.removeWhere((_, r) => r.status.finished && r.createdAt.isBefore(cutoff));
  }

  /// Appends a follow-up run's events to a kit's trace, renumbering them so
  /// sequence numbers stay unique.
  static List<RunEvent> appendTrace(List<RunEvent> trace, List<RunEvent> more) {
    var seq = trace.isEmpty ? 0 : trace.map((e) => e.seq).reduce((a, b) => a > b ? a : b);
    return [
      ...trace,
      for (final e in more) RunEvent(seq: ++seq, at: e.at, kind: e.kind, title: e.title, detail: e.detail, data: e.data),
    ];
  }

  RunRecord _start(String kind, String kitId, String ip, Future<CompKit> Function(RunRecord) body) {
    _gc();
    final record = RunRecord(id: newId(), kitId: kitId, kind: kind, ip: ip);
    _runs[record.id] = record;
    final locks = kind != 'build';
    if (locks) _busyKits.add(kitId);
    unawaited(() async {
      await _acquire();
      record.status = RunStatus.running;
      try {
        final kit = await body(record);
        record.kit = kit;
        final trace = kind == 'build' ? record.emitter.events : appendTrace(kits.traceOf(kitId), record.emitter.events);
        await kits.save(kit, trace);
        record.status = RunStatus.done;
      } on AgentFailure catch (e) {
        record.error = e.message;
        record.emitter.emit('error', 'Stopped', detail: e.message);
        record.status = RunStatus.failed;
      } on QlooException catch (e) {
        record.error = e.status == 401 || e.status == 403
            ? 'Qloo rejected the API key. Check QLOO_API_KEY and QLOO_BASE_URL on the server.'
            : 'Qloo did not answer (${e.message}). Please try again in a moment.';
        record.emitter.emit('error', 'Stopped', detail: record.error);
        record.status = RunStatus.failed;
      } on Object catch (e, st) {
        stderr.writeln('Run ${record.id} failed: $e\n$st');
        record.error = 'Something went wrong while building the kit. Please try again.';
        record.emitter.emit('error', 'Stopped', detail: record.error);
        record.status = RunStatus.failed;
      } finally {
        if (locks) _busyKits.remove(kitId);
        _release();
      }
    }());
    return record;
  }

  /// Edits to a shipped example go to a copy, so one visitor's refine or gut
  /// check never changes the example for everyone else.
  String _ownCopy(String kitId) {
    if (!kits.isExample(kitId)) return kitId;
    final id = newId(8);
    unawaited(kits.save(kits.get(kitId)!.copyWith(id: id), kits.traceOf(kitId)));
    return id;
  }

  void _lockable(String kitId) {
    if (_busyKits.contains(kitId)) {
      throw LimitExceeded('This kit is already being updated. Wait for that to finish, then try again.');
    }
  }

  RunRecord startBuild(Brief brief, String ip) {
    final problems = brief.problems();
    if (problems.isNotEmpty) throw ArgumentError(problems.first);
    if (llm == null && brief.anchors.isEmpty) {
      throw ArgumentError('Add at least one touchstone (this server has no language model to read a logline).');
    }
    _checkLimits(ip);
    final kitId = newId(8);
    return _start('build', kitId, ip, (r) => agent.build(brief, r.emitter, kitId: kitId));
  }

  RunRecord startRefine(String kitId, String message, String ip) {
    if (kits.get(kitId) == null) throw StateError('Unknown kit');
    final text = message.trim();
    if (text.isEmpty || text.length > 500) throw ArgumentError('Write a short request (up to 500 characters).');
    _lockable(kitId);
    _checkLimits(ip);
    kitId = _ownCopy(kitId);
    return _start('refine', kitId, ip, (r) async {
      // Read the kit when the run starts, not when it was queued.
      final kit = kits.get(kitId)!;
      r.emitter.step('Reading your request', '"$text"');
      final refinement = await Refiner(llm).refine(kit, text, r.emitter);
      if (refinement.changes.isEmpty) {
        r.emitter.decision('No changes to make', 'Try naming a title, a time window ("last 3 years"), a size ("more indie") or a market.');
        return kit;
      }
      r.emitter.decision('Updating the kit', refinement.changes.join(' · '));
      if (refinement.copyOnly && llm != null) {
        final rewritten = await agent.rewriteCopy(kit, r.emitter, refinement.copyInstructions);
        return rewritten.copyWith(version: kit.version + 1);
      }
      final rebuilt = await agent.build(refinement.brief, r.emitter,
          kitId: kitId, version: kit.version + 1, copyInstructions: refinement.copyInstructions);
      // A rebuild drops any earlier gut check: it measured the old brief.
      return rebuilt;
    });
  }

  RunRecord startGutCheck(String kitId, String ip) {
    if (kits.get(kitId) == null) throw StateError('Unknown kit');
    final model = llm;
    if (model == null) throw ArgumentError('The gut check needs a language model, and none is configured on this server.');
    _lockable(kitId);
    _checkLimits(ip);
    kitId = _ownCopy(kitId);
    return _start('gutcheck', kitId, ip, (r) async {
      final kit = kits.get(kitId)!;
      final baseline = await GutCheck(model, client).run(kit, r.emitter);
      return kit.copyWith(baseline: baseline);
    });
  }
}
