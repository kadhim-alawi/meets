import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:meets_core/meets_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/composer.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _composerKey = GlobalKey<ComposerState>();
  final _composerAnchor = GlobalKey();
  final _howKey = GlobalKey();
  final _agentsKey = GlobalKey();
  Health _health = Health.unknown;
  List<Example> _examples = const [];
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    Api.instance.health().then((h) {
      if (mounted) setState(() => _health = h);
    });
    Api.instance.examples().then((e) {
      if (mounted) setState(() => _examples = e);
    }).catchError((_) {});
  }

  Future<void> _start(Brief brief) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    lastBrief.value = brief;
    try {
      final (runId, _) = await Api.instance.startRun(brief);
      if (mounted) context.go('/run/$runId');
    } on ApiError catch (e) {
      setState(() => _error = e.message);
    } on Object {
      setState(() => _error = 'Could not reach the Meets server.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openExample(Example e) {
    if (e.kitId != null) {
      context.go('/kit/${e.kitId}');
      return;
    }
    _composerKey.currentState?.load(e.brief);
    Scrollable.ensureVisible(_composerAnchor.currentContext!, duration: const Duration(milliseconds: 400), curve: Curves.easeOutCubic);
  }

  void _scrollTo(GlobalKey key) =>
      Scrollable.ensureVisible(key.currentContext!, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final phone = context.isPhone;
    final wide = context.width >= 1040;
    final composer = Column(
      key: _composerAnchor,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Composer(key: _composerKey, onSubmit: _start, health: _health, busy: _busy, initial: lastBrief.value),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: context.t.bodyMedium?.copyWith(color: c.danger)),
        ],
      ],
    );
    final examples = _ExamplesColumn(examples: _examples, onOpen: _openExample);

    return Scaffold(
      body: SelectionArea(
        child: CustomScrollView(
          slivers: [
            if (_health.qloo == 'preview') const SliverToBoxAdapter(child: PreviewBanner()),
            SliverToBoxAdapter(
              child: PageWidth(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: phone ? 14 : 22),
                  child: Row(
                    children: [
                      const MeetsLogo(),
                      const Spacer(),
                      if (!phone) ...[
                        TextButton(onPressed: () => _scrollTo(_howKey), child: const Text('How it works')),
                        TextButton(onPressed: () => _scrollTo(_agentsKey), child: const Text('For AI agents')),
                      ],
                      TextButton.icon(
                        onPressed: () => launchUrl(Uri.parse('https://github.com/kadhim-alawi/meets')),
                        icon: const Icon(Icons.code_rounded, size: 18),
                        label: const Text('Source'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: PageWidth(
                child: Padding(
                  padding: EdgeInsets.only(top: phone ? 8 : 28, bottom: phone ? 24 : 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('COMPS & FIRST FANS · POWERED BY QLOO TASTE AI',
                          style: Fonts.monoW(12, weight: FontWeight.w600, color: c.accent, spacing: 1.6)),
                      const SizedBox(height: 16),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 980),
                        child: Text.rich(
                          TextSpan(children: [
                            const TextSpan(text: 'Every pitch says '),
                            TextSpan(text: '"it\'s X meets Y."', style: Fonts.display(phone ? 42 : 76, color: c.accent, italic: true)),
                            const TextSpan(text: ' Meets finds the right X and Y — and the people who\'ll love you.'),
                          ]),
                          style: Fonts.display(phone ? 42 : 76, color: c.ink, height: 1.0),
                        ),
                      ),
                      const SizedBox(height: 20),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: Text(
                          'An agent for authors, filmmakers, musicians, game devs, podcasters and comics. It reads Qloo\'s taste graph '
                          '— hundreds of millions of books, films, shows, artists, games and podcasts — to find recent, right-sized comps, '
                          'measure the audience behind them, and hand you the pitch copy and ad targeting to reach it.',
                          style: context.t.bodyLarge?.copyWith(color: c.muted, fontSize: phone ? 16 : 18.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: PageWidth(
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [Expanded(flex: 7, child: composer), const SizedBox(width: 28), Expanded(flex: 4, child: examples)],
                      )
                    : Column(children: [composer, const SizedBox(height: 32), examples]),
              ),
            ),
            SliverToBoxAdapter(child: SizedBox(height: phone ? 56 : 96)),
            SliverToBoxAdapter(child: PageWidth(child: _WhySection())),
            SliverToBoxAdapter(child: SizedBox(height: phone ? 56 : 96)),
            SliverToBoxAdapter(child: PageWidth(key: _howKey, child: _HowSection())),
            SliverToBoxAdapter(child: SizedBox(height: phone ? 56 : 96)),
            SliverToBoxAdapter(child: PageWidth(key: _agentsKey, child: _AgentsSection(health: _health))),
            const SliverToBoxAdapter(child: SizedBox(height: 72)),
            SliverToBoxAdapter(child: _Footer()),
          ],
        ),
      ),
    );
  }
}

class _ExamplesColumn extends StatelessWidget {
  const _ExamplesColumn({required this.examples, required this.onOpen});

  final List<Example> examples;
  final void Function(Example) onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('OR START FROM AN EXAMPLE', style: Fonts.monoW(11.5, weight: FontWeight.w600, color: c.muted, spacing: 1.4)),
        const SizedBox(height: 12),
        if (examples.isEmpty)
          Text('Examples load from the server.', style: context.t.bodySmall)
        else
          for (final e in examples)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => onOpen(e),
                child: Ink(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: c.line),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(color: c.paper, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.line)),
                        child: Icon(formatIcon(e.brief.format), size: 19, color: c.accent),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(e.title, style: context.t.titleSmall),
                            const SizedBox(height: 3),
                            Text(e.blurb, style: context.t.bodySmall),
                            const SizedBox(height: 6),
                            Text(
                              '${e.brief.title.isEmpty ? '' : '"${e.brief.title}" · '}like ${e.brief.anchors.map((a) => a.name).join(' + ')}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Fonts.monoW(11, color: c.faint),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(e.kitId != null ? Icons.arrow_forward_rounded : Icons.edit_outlined, size: 18, color: c.muted),
                    ],
                  ),
                ),
              ),
            ),
      ],
    );
  }
}

class _WhySection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final cards = [
      (
        Icons.trending_down_rounded,
        'Chatbots name the obvious hits',
        'Ask an LLM for comps and you get the phenomenon everyone already knows. Agents and buyers roll their eyes at '
            '"Harry Potter meets The Hunger Games". Meets reads Qloo popularity percentiles and digs below the blockbusters '
            'for comps your size.',
      ),
      (
        Icons.update_rounded,
        'Chatbots stop at their training cutoff',
        'Buyers want proof the audience is buying now. Meets filters Qloo by release, publication or air date, so your '
            'comps are from this market, not a decade ago.',
      ),
      (
        Icons.groups_2_outlined,
        'Chatbots guess the audience',
        'Qloo measures it: affinity across 250M+ entities, demographic skew, taste descriptors and where fans cluster '
            'city by city. Every claim in your kit traces to a Qloo call you can inspect.',
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(eyebrow: 'Why a taste graph', title: 'Comps are a data problem.'),
        LayoutBuilder(builder: (context, box) {
          final cols = box.maxWidth >= 900 ? 3 : 1;
          final w = cols == 1 ? box.maxWidth : (box.maxWidth - 28) / 3;
          return Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              for (final (icon, title, body) in cards)
                SizedBox(
                  width: w,
                  child: Panel(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(icon, color: c.accent, size: 26),
                        const SizedBox(height: 14),
                        Text(title, style: context.t.headlineSmall),
                        const SizedBox(height: 10),
                        Text(body, style: context.t.bodyMedium?.copyWith(color: c.muted)),
                      ],
                    ),
                  ),
                ),
            ],
          );
        }),
      ],
    );
  }
}

class _HowSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final steps = [
      ('Resolve', 'Your touchstones become exact Qloo entities. If you only wrote a logline, the agent proposes touchstones and themes — and keeps only the ones Qloo can find.', 'GET /search · /entities · /v2/tags'),
      ('Scan', 'One affinity scan per category: comps from your shelf, plus what the same people watch, read, play and listen to. Filtered by recency and weighted by age if you ask.', 'GET /v2/insights · filter.type · signal.interests.entities · filter.release_year.min · signal.demographics.age'),
      ('Right-size', 'When the top results are blockbusters, the agent digs below the top 0.1% for comps your size, then tests pairings to find the two that triangulate your work.', 'filter.popularity.max · filter.results.entities · /v2/analysis/compare'),
      ('Measure the audience', 'Age and gender skew, the tags that define their taste, and the cities where they over-index — including hidden gems.', 'filter.type = urn:demographics · urn:tag · urn:heatmap'),
      ('Write & check', 'An LLM writes the pitch copy using only entities Qloo returned (it cites them by reference, so it can\'t invent titles). Your own comps get a verdict and a swap.', 'Claude · grounded {{entity}} references · comp check'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(eyebrow: 'How it works', title: 'An agent that shows its work.'),
        for (var i = 0; i < steps.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: c.line))),
            child: LayoutBuilder(builder: (context, box) {
              final narrow = box.maxWidth < 760;
              final head = Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 44, child: Text('0${i + 1}', style: Fonts.monoW(13, weight: FontWeight.w600, color: c.accent))),
                  Expanded(child: Text(steps[i].$1, style: context.t.headlineSmall)),
                ],
              );
              final body = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(steps[i].$2, style: context.t.bodyMedium),
                  const SizedBox(height: 8),
                  Text(steps[i].$3, style: Fonts.monoW(11.5, color: c.teal)),
                ],
              );
              return narrow
                  ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [head, const SizedBox(height: 8), Padding(padding: const EdgeInsets.only(left: 44), child: body)])
                  : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 340, child: head), Expanded(child: body)]);
            }),
          ),
      ],
    );
  }
}

class _AgentsSection extends StatelessWidget {
  const _AgentsSection({required this.health});

  final Health health;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final url = '${Api.instance.base}/mcp';
    final snippet = '{\n  "mcpServers": {\n    "meets": { "type": "http", "url": "$url" }\n  }\n}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          eyebrow: 'For AI agents',
          title: 'Give your own agent taste.',
          subtitle: 'Meets is also an MCP server. Add it to Claude, an IDE or any MCP client and call find_comps or check_comps.',
        ),
        Panel(
          color: c.ink,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: SelectableText(snippet, style: Fonts.monoW(13.5, color: c.paper))),
              IconButton(
                tooltip: 'Copy',
                onPressed: () => copyText(context, snippet, what: 'MCP config copied'),
                icon: Icon(Icons.copy_rounded, color: c.paper, size: 18),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          health.mcp ? 'Endpoint: $url (Streamable HTTP, JSON responses).' : 'The MCP endpoint is enabled when the server has a Qloo key.',
          style: context.t.bodySmall,
        ),
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      color: c.surfaceAlt,
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: PageWidth(
        child: Wrap(
          spacing: 24,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const MeetsLogo(size: 22),
            Text('Built for the Qloo Agentic Hackathon · Taste data by Qloo · Agent and writing by Claude · MIT licensed',
                style: context.t.bodySmall),
            Text('Affinity is aggregate taste, never a sales forecast or a profile of any person.', style: context.t.bodySmall),
          ],
        ),
      ),
    );
  }
}
