import 'package:flutter/material.dart';
import 'package:meets_core/meets_core.dart';

import '../../theme.dart';
import '../common.dart';
import '../timeline.dart';

/// The pitch copy blocks, each one copyable.
class CopySection extends StatelessWidget {
  const CopySection({super.key, required this.kit});

  final CompKit kit;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final llm = kit.copy.any((b) => b.author == 'llm');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          eyebrow: 'Pitch kit · ${llm ? 'written by the agent from Qloo evidence only' : 'written from the evidence'}',
          title: 'Ready to paste',
          subtitle: 'Every title in here came back from Qloo for this brief. Edit freely — it\'s yours.',
        ),
        for (final block in kit.copy)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Panel(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(block.title, style: context.t.titleMedium),
                            if (block.hint.isNotEmpty) Text(block.hint, style: context.t.bodySmall),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Copy',
                        onPressed: () => copyText(context, block.body, what: '${block.title} copied'),
                        icon: Icon(Icons.copy_rounded, size: 18, color: c.muted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (block.id == 'comp_line') ...[
                    SelectableText(block.body.split('\n').first, style: Fonts.display(26, color: c.ink, height: 1.2)),
                    if (block.body.contains('\n'))
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: SelectableText(block.body.split('\n').skip(1).join('\n').trim(),
                            style: context.t.bodyLarge?.copyWith(height: 1.6, color: c.muted)),
                      ),
                  ] else
                    SelectableText(block.body, style: context.t.bodyLarge?.copyWith(height: 1.6)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Copyable targeting lists per platform.
class TargetingSection extends StatelessWidget {
  const TargetingSection({super.key, required this.kit});

  final CompKit kit;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final wide = context.width >= 900;
    final panels = [
      for (final t in kit.targeting)
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(t.platform, style: context.t.titleMedium)),
                  TextButton.icon(
                    onPressed: () => copyText(context, t.items.join('\n'), what: '${t.items.length} ${t.platform} targets copied'),
                    icon: const Icon(Icons.copy_all_rounded, size: 16),
                    label: const Text('Copy all'),
                  ),
                ],
              ),
              Text(t.how, style: context.t.bodySmall),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final item in t.items)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: c.paper, borderRadius: BorderRadius.circular(8), border: Border.all(color: c.line)),
                      child: Text(item, style: Fonts.sansW(13, FontWeight.w500, color: c.ink)),
                    ),
                ],
              ),
            ],
          ),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          eyebrow: 'Targeting kit',
          title: 'Reach them',
          subtitle: 'Interest and lookalike lists for the platforms that matter for this format, taken straight from the scans.',
        ),
        if (wide && panels.length > 1)
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              for (final p in panels) SizedBox(width: (context.width.clamp(0, 1180) - 340) / 2, child: p),
            ],
          )
        else
          for (final p in panels) Padding(padding: const EdgeInsets.only(bottom: 12), child: p),
      ],
    );
  }
}

/// "What would a plain chatbot have said?" - checked against Qloo.
class GutCheckSection extends StatelessWidget {
  const GutCheckSection({super.key, required this.kit, required this.onRun, required this.running, required this.available, this.events = const []});

  final CompKit kit;
  final VoidCallback onRun;
  final bool running;
  final bool available;
  final List<RunEvent> events;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final baseline = kit.baseline;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          eyebrow: 'Gut check',
          title: 'Why not just ask a chatbot?',
          subtitle: 'Same brief, same model, no Qloo. Then every suggestion is looked up and measured against your audience.',
        ),
        if (baseline == null)
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  available
                      ? 'Run the comparison to see which of a plain LLM\'s comps would actually hold up in front of a buyer.'
                      : 'The gut check needs a language model, and this server has none configured.',
                  style: context.t.bodyMedium,
                ),
                const SizedBox(height: 14),
                if (running) AgentTimeline(events: events, running: true, compact: true, showCalls: false),
                if (!running)
                  OutlinedButton.icon(
                    onPressed: available ? onRun : null,
                    icon: const Icon(Icons.compare_arrows_rounded, size: 18),
                    label: const Text('Run the gut check'),
                  ),
              ],
            ),
          )
        else
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(baseline.summary, style: Fonts.display(23, color: c.ink, height: 1.2)),
                const SizedBox(height: 4),
                Text('Plain LLM: ${baseline.model}, no tools.', style: Fonts.monoW(11, color: c.faint)),
                const SizedBox(height: 14),
                for (final item in baseline.items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 104,
                          child: switch (item.verdict) {
                            'strong' => Pill('Holds up', color: c.teal, icon: Icons.check_rounded),
                            'too_big' => Pill('Too big', color: c.danger),
                            'dated' => Pill('Too old', color: c.gold),
                            'weak_fit' => Pill('Weak fit', color: c.muted),
                            _ => Pill('Not in Qloo', color: c.faint),
                          },
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(item.resolved?.name ?? item.name,
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: Fonts.sansW(15, FontWeight.w600, color: c.ink)),
                        ),
                        if (item.resolved != null)
                          Text(
                            [if (item.resolved!.year != null) '${item.resolved!.year}', topPercentLabel(item.resolved!.popularity)].join(' · '),
                            style: Fonts.monoW(11, color: c.faint),
                          ),
                        if (item.fit != null) ...[const SizedBox(width: 12), FitMeter(fit: item.fit!, label: false)],
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The audit trail: every stage, decision and Qloo call, plus limits.
class TraceSection extends StatefulWidget {
  const TraceSection({super.key, required this.kit, required this.trace});

  final CompKit kit;
  final List<RunEvent> trace;

  @override
  State<TraceSection> createState() => _TraceSectionState();
}

class _TraceSectionState extends State<TraceSection> {
  bool _open = false;
  bool _calls = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = widget.kit.stats;
    final endpoints = <String>{
      for (final e in widget.trace)
        if (e.kind == 'qloo' && e.data['path'] != null) '${e.data['path']}${_type(e.data)}',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          eyebrow: 'Audit trail',
          title: 'How Meets got here',
          subtitle: '${s.qlooCalls} Qloo calls${s.cachedCalls > 0 ? ' (${s.cachedCalls} cached)' : ''} · '
              '${(s.durationMs / 1000).toStringAsFixed(1)}s${s.model == null ? ' · no language model' : ' · ${s.model}'}',
        ),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Qloo endpoints used', style: context.t.titleSmall),
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: [for (final e in endpoints) Pill(e, color: c.teal)]),
              const SizedBox(height: 18),
              Text('Limits', style: context.t.titleSmall),
              const SizedBox(height: 6),
              for (final n in widget.kit.notes)
                Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('— $n', style: context.t.bodySmall)),
              const SizedBox(height: 10),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () => setState(() => _open = !_open),
                    icon: Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded),
                    label: Text(_open ? 'Hide the agent\'s steps' : 'Show the agent\'s steps (${widget.trace.length})'),
                  ),
                  if (_open) ...[
                    const Spacer(),
                    FilterChip(label: const Text('Every Qloo call'), selected: _calls, onSelected: (v) => setState(() => _calls = v)),
                  ],
                ],
              ),
              if (_open) AgentTimeline(events: widget.trace, compact: true, showCalls: _calls),
            ],
          ),
        ),
      ],
    );
  }

  String _type(Json data) {
    final params = asJson(data['params']);
    final type = asString(params['filter.type']);
    return type == null ? '' : ' · ${type.replaceFirst('urn:entity:', '').replaceFirst('urn:', '')}';
  }
}
