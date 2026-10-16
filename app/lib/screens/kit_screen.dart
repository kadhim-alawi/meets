import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:meets_core/meets_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/kit/comps.dart';
import '../widgets/kit/deliverables.dart';
import '../widgets/kit/hero.dart';
import '../widgets/kit/insights.dart';
import '../widgets/timeline.dart';

/// The comp kit: the deliverable, with refine and gut-check built in.
class KitScreen extends StatefulWidget {
  const KitScreen({super.key, required this.kitId, this.handoff});

  final String kitId;
  final KitHandoff? handoff;

  @override
  State<KitScreen> createState() => _KitScreenState();
}

class _Section {
  _Section(this.id, this.label);

  final String id;
  final String label;
  final GlobalKey key = GlobalKey();
}

class _KitScreenState extends State<KitScreen> {
  CompKit? _kit;
  List<RunEvent> _trace = const [];
  String? _error;
  Health _health = Health.unknown;

  // Background runs (refine / gut check).
  StreamSubscription<RunSnapshot>? _sub;
  String? _activeRun; // 'refine' | 'gutcheck'
  final List<RunEvent> _runEvents = [];
  final _refine = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    final h = widget.handoff;
    if (h != null && h.kit.id == widget.kitId) {
      _kit = h.kit;
      _trace = h.trace;
    } else {
      _load();
    }
    Api.instance.health().then((v) {
      if (mounted) setState(() => _health = v);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _refine.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final (kit, trace) = await Api.instance.kit(widget.kitId);
      if (mounted) {
        setState(() {
          _kit = kit;
          _trace = trace;
          _error = null;
        });
      }
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object {
      if (mounted) setState(() => _error = 'Could not reach the Meets server.');
    }
  }

  Future<void> _startBackground(String kind, Future<String> Function() start) async {
    if (_activeRun != null) return;
    setState(() {
      _activeRun = kind;
      _runEvents.clear();
    });
    try {
      final runId = await start();
      _sub = Api.instance.follow(runId).listen((snap) {
        if (!mounted) return;
        setState(() => _runEvents.addAll(snap.events));
        if (snap.status.finished) {
          final kit = snap.kit;
          setState(() {
            _activeRun = null;
            if (kit != null) _kit = kit;
          });
          final msg = snap.status == RunStatus.failed
              ? (snap.error ?? 'That did not work.')
              : kind == 'refine'
                  ? 'Kit updated to v${kit?.version ?? ''}'
                  : 'Gut check complete';
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
          if (kit != null && kit.id != widget.kitId) {
            // An example was edited: the server worked on a copy, which has its own page and share link.
            context.go('/kit/${kit.id}');
          } else if (kit != null) {
            // The server stitches and renumbers the audit trail; fetch it.
            _load();
          }
        }
      }, onError: (Object e) {
        if (!mounted) return;
        setState(() => _activeRun = null);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _activeRun = null);
      final message = e is ApiError ? e.message : 'Could not reach the Meets server. Please try again.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  void _submitRefine() {
    final text = _refine.text.trim();
    if (text.isEmpty || _kit == null) return;
    _refine.clear();
    _startBackground('refine', () => Api.instance.refine(_kit!.id, text));
  }

  List<_Section> _sections(CompKit kit) => [
        _Section('top', 'Comp line'),
        _Section('comps', 'Comps'),
        if (kit.compCheck.isNotEmpty) _Section('check', 'Comp check'),
        _Section('audience', 'Audience'),
        if (kit.cross.isNotEmpty) _Section('beyond', 'Beyond the shelf'),
        if (kit.channels.isNotEmpty) _Section('channels', 'Where to reach them'),
        _Section('copy', 'Pitch copy'),
        _Section('targeting', 'Targeting'),
        _Section('gut', 'Gut check'),
        _Section('trace', 'Audit trail'),
      ];

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final kit = _kit;
    if (kit == null) {
      return Scaffold(
        body: Center(
          child: _error == null
              ? CircularProgressIndicator(color: c.accent)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, style: context.t.bodyLarge),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: () => context.go('/'), child: const Text('Start a new kit')),
                  ],
                ),
        ),
      );
    }
    final sections = _sections(kit);
    Widget section(String id, Widget child) {
      final s = sections.firstWhere((x) => x.id == id);
      return Padding(key: s.key, padding: const EdgeInsets.only(bottom: 64), child: child);
    }

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        section(
          'top',
          KitHero(
            kit: kit,
            proof: kit.baseline == null
                ? null
                : _GutStrip(
                    baseline: kit.baseline!,
                    onSeeWhy: () {
                      final ctx = sections.firstWhere((s) => s.id == 'gut').key.currentContext;
                      if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
                    },
                  ),
            actions: [
              FilledButton.icon(
                onPressed: () => copyText(context, Api.instance.kitLink(kit.id), what: 'Link copied — anyone with it can open this kit'),
                icon: const Icon(Icons.link_rounded, size: 18),
                label: const Text('Share link'),
              ),
              OutlinedButton.icon(
                onPressed: () => launchUrl(Uri.parse(Api.instance.exportUrl(kit.id, 'md'))),
                icon: const Icon(Icons.description_outlined, size: 18),
                label: const Text('Export .md'),
              ),
              OutlinedButton.icon(
                onPressed: () => launchUrl(Uri.parse(Api.instance.exportUrl(kit.id, 'csv'))),
                icon: const Icon(Icons.table_chart_outlined, size: 18),
                label: const Text('Export .csv'),
              ),
            ],
          ),
        ),
        section('comps', CompsSection(kit: kit)),
        if (kit.compCheck.isNotEmpty) section('check', CompCheckSection(kit: kit)),
        section('audience', AudienceSection(kit: kit)),
        if (kit.cross.isNotEmpty)
          section(
            'beyond',
            BeyondSection(
              kit: kit,
              scans: kit.cross,
              eyebrow: 'Beyond the shelf · cross-domain affinity',
              title: 'What else they love',
              subtitle: 'Use these for interest targeting, collaborations and the "if you like…" line in your pitch.',
            ),
          ),
        if (kit.channels.isNotEmpty)
          section(
            'channels',
            BeyondSection(
              kit: kit,
              scans: kit.channels,
              eyebrow: 'Channels',
              title: 'Where to reach them',
              subtitle: 'Shows to advertise on or pitch for a guest spot, and brands this audience already buys from.',
            ),
          ),
        section('copy', CopySection(kit: kit)),
        section('targeting', TargetingSection(kit: kit)),
        section(
          'gut',
          GutCheckSection(
            kit: kit,
            available: _health.llm && _health.canBuild,
            running: _activeRun == 'gutcheck',
            events: _runEvents,
            onRun: () => _startBackground('gutcheck', () => Api.instance.gutCheck(kit.id)),
          ),
        ),
        section('trace', TraceSection(kit: kit, trace: _trace)),
        const SizedBox(height: 120),
      ],
    );

    final wide = context.isWide;
    return Scaffold(
      body: Stack(
        children: [
          SelectionArea(
            child: CustomScrollView(
              controller: _scroll,
              slivers: [
                if (kit.mode == 'preview') const SliverToBoxAdapter(child: PreviewBanner()),
                SliverToBoxAdapter(
                  child: PageWidth(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Row(
                        children: [
                          MeetsLogo(onTap: () => context.go('/')),
                          const Spacer(),
                          OutlinedButton.icon(
                            onPressed: () {
                              lastBrief.value = kit.brief;
                              context.go('/');
                            },
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: Text(context.isPhone ? 'New' : 'New kit'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: PageWidth(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: wide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(width: 200, child: _Nav(sections: sections)),
                                const SizedBox(width: 40),
                                Expanded(child: content),
                              ],
                            )
                          : content,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(left: 0, right: 0, bottom: 0, child: _refineDock(kit)),
        ],
      ),
    );
  }

  Widget _refineDock(CompKit kit) {
    final c = context.c;
    final busy = _activeRun == 'refine';
    final canRefine = _health.canBuild;
    if (!canRefine) return const SizedBox.shrink();
    return SafeArea(
      top: false,
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 760),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: c.line),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.14), blurRadius: 30, offset: const Offset(0, 10))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: SingleChildScrollView(
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
                    child: AgentTimeline(events: _runEvents, running: true, compact: true, showCalls: false),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
                child: Row(
                  children: [
                    Icon(Icons.auto_awesome_outlined, size: 18, color: c.accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _refine,
                        enabled: !busy,
                        onSubmitted: (_) => _submitRefine(),
                        maxLength: 500,
                        decoration: InputDecoration(
                          counterText: '',
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          hintText: busy ? 'Updating your kit…' : 'Refine: "only the last 3 years", "more indie", "UK market", "add Severance"',
                        ),
                      ),
                    ),
                    IconButton.filled(
                      onPressed: busy ? null : _submitRefine,
                      style: IconButton.styleFrom(backgroundColor: c.accent, foregroundColor: c.onAccent),
                      icon: busy
                          ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: c.onAccent))
                          : const Icon(Icons.arrow_upward_rounded, size: 20),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The gut check up front: what a plain chatbot suggested, and how much of it
/// fails once Qloo measures it against this audience.
class _GutStrip extends StatelessWidget {
  const _GutStrip({required this.baseline, required this.onSeeWhy});

  final BaselineResult baseline;
  final VoidCallback onSeeWhy;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final judged = baseline.items.where((i) => i.verdict != 'touchstone').toList();
    if (judged.isEmpty) return const SizedBox.shrink();
    final failed = judged.where((i) => i.verdict != 'strong').length;
    int n(String v) => judged.where((i) => i.verdict == v).length;
    final names = judged.take(3).map((i) => i.name).join(', ');
    final more = judged.length > 3 ? ' and ${judged.length - 3} more' : '';
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: failed > 0 ? c.accent.withValues(alpha: 0.55) : c.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'GUT CHECK · THE SAME MODEL, WITHOUT QLOO',
              style: Fonts.monoW(11, weight: FontWeight.w600, color: c.accent, spacing: 1.2),
            ),
            const SizedBox(height: 10),
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'A plain chatbot suggested '),
                  TextSpan(
                    text: names,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: '$more. '),
                  TextSpan(
                    text: failed == 0
                        ? 'Measured by Qloo against this audience, all ${judged.length} hold up.'
                        : 'Measured by Qloo against this audience, $failed of ${judged.length} don\'t hold up.',
                    style: TextStyle(color: c.ink, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              style: Fonts.sansW(16, FontWeight.w400, color: c.muted, height: 1.45),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (n('too_big') > 0) Pill('${n('too_big')} too big', color: c.danger),
                if (n('dated') > 0) Pill('${n('dated')} too old', color: c.gold),
                if (n('weak_fit') > 0) Pill('${n('weak_fit')} weak fit', color: c.muted),
                if (n('not_found') > 0) Pill('${n('not_found')} not in Qloo', color: c.faint),
                if (n('strong') > 0) Pill('${n('strong')} hold up', color: c.teal),
                TextButton.icon(
                  onPressed: onSeeWhy,
                  icon: const Icon(Icons.arrow_downward_rounded, size: 16),
                  label: const Text('See why'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Nav extends StatelessWidget {
  const _Nav({required this.sections});

  final List<_Section> sections;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('IN THIS KIT', style: Fonts.monoW(11, weight: FontWeight.w600, color: c.faint, spacing: 1.4)),
          const SizedBox(height: 10),
          for (final s in sections)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                final ctx = s.key.currentContext;
                if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
                child: Text(s.label, style: Fonts.sansW(14.5, FontWeight.w500, color: c.muted)),
              ),
            ),
        ],
      ),
    );
  }
}
