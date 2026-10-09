import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:meets_core/meets_core.dart';

import '../api.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/timeline.dart';

/// Watches the agent work, then hands over to the kit.
class RunScreen extends StatefulWidget {
  const RunScreen({super.key, required this.runId});

  final String runId;

  @override
  State<RunScreen> createState() => _RunScreenState();
}

class _RunScreenState extends State<RunScreen> {
  final List<RunEvent> _events = [];
  StreamSubscription<RunSnapshot>? _sub;
  RunStatus _status = RunStatus.queued;
  String? _error;
  bool _calls = true;
  final _started = DateTime.now();
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => mounted ? setState(() {}) : null);
    _sub = Api.instance.follow(widget.runId).listen(
      (snap) {
        setState(() {
          _events.addAll(snap.events);
          _status = snap.status;
          _error = snap.error;
        });
        final kit = snap.kit;
        if (snap.status == RunStatus.done && kit != null) {
          Future<void>.delayed(const Duration(milliseconds: 700), () {
            if (mounted) context.go('/kit/${kit.id}', extra: KitHandoff(kit, List.of(_events)));
          });
        }
      },
      onError: (Object e) => setState(() {
        _status = RunStatus.failed;
        _error = e is ApiError ? e.message : 'Lost contact with the server.';
      }),
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final brief = lastBrief.value;
    final calls = _events.where((e) => e.kind == 'qloo').length;
    final secs = DateTime.now().difference(_started).inSeconds;
    final failed = _status == RunStatus.failed;
    return Scaffold(
      body: SelectionArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            PageWidth(
              max: 860,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 22),
                child: Row(children: [MeetsLogo(onTap: () => context.go('/'))]),
              ),
            ),
            PageWidth(
              max: 860,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 18),
                  Text(failed ? 'STOPPED' : (_status == RunStatus.done ? 'DONE' : 'WORKING · ${secs}s · $calls QLOO CALLS'),
                      style: Fonts.monoW(12, weight: FontWeight.w600, color: failed ? c.danger : c.accent, spacing: 1.4)),
                  const SizedBox(height: 12),
                  Text(
                    failed
                        ? 'The agent couldn\'t finish.'
                        : brief == null
                            ? 'Building your comp kit'
                            : 'Finding comps for ${brief.title.isEmpty ? 'your ${brief.format.noun}' : brief.title}',
                    style: context.isPhone ? context.t.displaySmall : context.t.displayMedium,
                  ),
                  if (brief != null && brief.anchors.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text('Like ${brief.anchors.map((a) => a.name).join(' + ')}', style: context.t.bodyLarge?.copyWith(color: c.muted)),
                  ],
                  const SizedBox(height: 28),
                  if (failed)
                    Panel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_error ?? 'Something went wrong.', style: context.t.bodyLarge),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: () => context.go('/'),
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            label: const Text('Edit the brief'),
                          ),
                        ],
                      ),
                    ),
                  if (failed) const SizedBox(height: 20),
                  Panel(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text('Agent log', style: context.t.titleMedium)),
                            FilterChip(label: const Text('Every Qloo call'), selected: _calls, onSelected: (v) => setState(() => _calls = v)),
                          ],
                        ),
                        AgentTimeline(events: _events, running: !_status.finished, showCalls: _calls),
                      ],
                    ),
                  ),
                  const SizedBox(height: 60),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
