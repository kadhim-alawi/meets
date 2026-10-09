import 'package:flutter/material.dart';
import 'package:meets_core/meets_core.dart';

import '../theme.dart';

/// The agent's narration: stages, Qloo calls, decisions and warnings.
class AgentTimeline extends StatelessWidget {
  const AgentTimeline({super.key, required this.events, this.running = false, this.compact = false, this.showCalls = true});

  final List<RunEvent> events;
  final bool running;
  final bool compact;

  /// When false, individual Qloo calls are folded into a count per stage.
  final bool showCalls;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    var hiddenCalls = 0;
    for (var i = 0; i < events.length; i++) {
      final e = events[i];
      if (!showCalls && e.kind == 'qloo') {
        hiddenCalls++;
        final next = i + 1 < events.length ? events[i + 1] : null;
        if (next == null || next.kind != 'qloo') {
          rows.add(_FoldedCalls(count: hiddenCalls, key: ValueKey('fold$i')));
          hiddenCalls = 0;
        }
        continue;
      }
      // Keyed by position: the list only grows, and seq can repeat across
      // stitched runs.
      rows.add(_EventRow(event: e, compact: compact, key: ValueKey('e$i')));
    }
    if (running) rows.add(const _Working());
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }
}

class _Appear extends StatelessWidget {
  const _Appear({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        builder: (context, t, child) => Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, (1 - t) * 8), child: child),
        ),
        child: child,
      );
}

class _EventRow extends StatelessWidget {
  const _EventRow({super.key, required this.event, required this.compact});

  final RunEvent event;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final e = event;
    final (icon, color) = switch (e.kind) {
      'step' => (Icons.radio_button_checked_rounded, c.ink),
      'qloo' => (Icons.hub_outlined, c.teal),
      'decision' => (Icons.alt_route_rounded, c.accent),
      'llm' => (Icons.auto_awesome_outlined, c.gold),
      'warn' => (Icons.error_outline_rounded, c.gold),
      'done' => (Icons.check_circle_rounded, c.teal),
      'error' => (Icons.cancel_outlined, c.danger),
      _ => (Icons.circle_outlined, c.muted),
    };
    final isStep = e.kind == 'step' || e.kind == 'done' || e.kind == 'error';
    final data = e.data;
    final count = data['count'];
    final cached = data['cached'] == true;
    final failed = data['error'] == true || (data['status'] is int && (data['status'] as int) >= 400);
    return _Appear(
      child: Padding(
        padding: EdgeInsets.only(top: isStep ? (compact ? 10 : 14) : 3, bottom: 3, left: isStep ? 0 : 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: isStep ? 17 : 14, color: failed ? c.danger : color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        e.title,
                        style: isStep
                            ? Fonts.sansW(compact ? 14 : 15, FontWeight.w700, color: c.ink)
                            : Fonts.sansW(13.5, e.kind == 'decision' ? FontWeight.w600 : FontWeight.w400, color: c.ink),
                      ),
                      if (e.kind == 'qloo' && data['path'] != null)
                        Text(
                          '${data['path']}${count is int ? ' · $count' : ''}${cached ? ' · cached' : data['ms'] is int ? ' · ${data['ms']}ms' : ''}',
                          style: Fonts.monoW(11, color: failed ? c.danger : c.faint),
                        ),
                    ],
                  ),
                  if (e.detail != null && e.detail!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(e.detail!, style: context.t.bodySmall),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FoldedCalls extends StatelessWidget {
  const _FoldedCalls({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(left: 6, top: 3, bottom: 3),
      child: Row(children: [
        Icon(Icons.hub_outlined, size: 14, color: c.teal),
        const SizedBox(width: 10),
        Text('$count Qloo call${count == 1 ? '' : 's'}', style: Fonts.monoW(11.5, color: c.muted)),
      ]),
    );
  }
}

class _Working extends StatefulWidget {
  const _Working();

  @override
  State<_Working> createState() => _WorkingState();
}

class _WorkingState extends State<_Working> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(top: 10, left: 2),
      child: AnimatedBuilder(
        animation: _a,
        builder: (context, _) => Row(
          children: [
            for (var i = 0; i < 3; i++)
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(right: 5),
                decoration: BoxDecoration(
                  color: c.accent.withValues(alpha: 0.25 + 0.75 * (((_a.value * 3 - i) % 3) < 1 ? 1 : 0)),
                  shape: BoxShape.circle,
                ),
              ),
            const SizedBox(width: 6),
            Text('Working', style: Fonts.monoW(11.5, color: c.muted)),
          ],
        ),
      ),
    );
  }
}
