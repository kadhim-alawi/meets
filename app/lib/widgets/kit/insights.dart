import 'package:flutter/material.dart';
import 'package:meets_core/meets_core.dart';

import '../../theme.dart';
import '../common.dart';

/// Verdicts on the comps the creator planned to use.
class CompCheckSection extends StatelessWidget {
  const CompCheckSection({super.key, required this.kit});

  final CompKit kit;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final swaps = kit.compCheck.where((v) => v.verdict != 'keep').length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          eyebrow: 'Comp check · ${kit.compCheck.length} checked',
          title: swaps == 0 ? 'Your comps hold up' : '$swaps of your comps could hurt you',
          subtitle: 'Each one measured for audience overlap, size and recency against the same Qloo signal.',
        ),
        for (final v in kit.compCheck)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Panel(
              padding: const EdgeInsets.all(16),
              child: LayoutBuilder(builder: (context, box) {
                final narrow = box.maxWidth < 620;
                final verdict = switch (v.verdict) {
                  'keep' => Pill('Keep', color: c.teal, icon: Icons.check_rounded, filled: true),
                  'swap' => Pill('Swap', color: c.accent, icon: Icons.swap_horiz_rounded, filled: true),
                  _ => Pill('Not found', color: c.faint),
                };
                final left = Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (v.resolved != null) Cover(entity: v.resolved!, width: 48, height: 70, radius: 6),
                    if (v.resolved != null) const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            verdict,
                            const SizedBox(width: 10),
                            Flexible(child: Text(v.resolved?.name ?? v.input, style: Fonts.display(21, color: c.ink))),
                          ]),
                          const SizedBox(height: 8),
                          for (final r in v.reasons)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Text('— $r', style: context.t.bodyMedium?.copyWith(color: c.muted)),
                            ),
                        ],
                      ),
                    ),
                  ],
                );
                final swap = v.swap == null
                    ? null
                    : Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: c.paper, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.line)),
                        child: Row(
                          children: [
                            Cover(entity: v.swap!.entity, width: 40, height: 58, radius: 5),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('TRY INSTEAD', style: Fonts.monoW(10.5, weight: FontWeight.w600, color: c.accent, spacing: 1)),
                                  const SizedBox(height: 2),
                                  Text(v.swap!.entity.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.t.titleSmall),
                                  const SizedBox(height: 4),
                                  Text('${v.swap!.size.label} · ${v.swap!.entity.year ?? ''}', style: context.t.bodySmall),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                if (narrow) {
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [left, if (swap != null) ...[const SizedBox(height: 12), swap]]);
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [Expanded(child: left), if (swap != null) ...[const SizedBox(width: 16), SizedBox(width: 250, child: swap)]],
                );
              }),
            ),
          ),
      ],
    );
  }
}

/// Demographic skew, taste descriptors and markets.
class AudienceSection extends StatelessWidget {
  const AudienceSection({super.key, required this.kit});

  final CompKit kit;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final audience = kit.audience;
    final f = kit.brief.format;
    final wide = context.width >= 900;
    final demo = audience == null || audience.age.isEmpty ? null : _Demographics(profile: audience);
    final markets = kit.markets.isEmpty ? null : _Markets(kit: kit);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          eyebrow: 'Audience · from Qloo demographics, taste analysis and heatmaps',
          title: 'Your first ${f.audience}',
          subtitle: audience == null || audience.isEmpty ? null : describeAudience(audience, f.audience),
        ),
        if (wide && demo != null && markets != null)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Expanded(child: demo), const SizedBox(width: 14), Expanded(child: markets)],
          )
        else ...[
          ?demo,
          if (demo != null && markets != null) const SizedBox(height: 14),
          ?markets,
        ],
        if (audience != null && audience.descriptors.isNotEmpty) ...[
          const SizedBox(height: 14),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('What their taste is made of', style: context.t.titleMedium),
                const SizedBox(height: 4),
                Text('Qloo tags that over-index for people who love your touchstones.', style: context.t.bodySmall),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < audience.descriptors.length; i++)
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: i < 3 ? 14 : 11, vertical: i < 3 ? 8 : 6),
                        decoration: BoxDecoration(
                          color: i < 3 ? c.ink : c.paper,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: i < 3 ? c.ink : c.line),
                        ),
                        child: Text(audience.descriptors[i].name,
                            style: Fonts.sansW(i < 3 ? 15 : 13.5, FontWeight.w600, color: i < 3 ? c.paper : c.ink)),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Demographics extends StatelessWidget {
  const _Demographics({required this.profile});

  final AudienceProfile profile;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final maxAbs = profile.age.values.fold<double>(0.15, (m, v) => v.abs() > m ? v.abs() : m);
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Age skew', style: context.t.titleMedium),
          const SizedBox(height: 4),
          Text('Right of centre: over-indexes vs. the general population.', style: context.t.bodySmall),
          const SizedBox(height: 14),
          for (final band in AgeBand.values)
            if (profile.age[band] != null) _bar(context, band.label, profile.age[band]!, maxAbs),
          if (profile.female != null && profile.male != null) ...[
            const SizedBox(height: 14),
            Text('Gender skew', style: context.t.titleSmall),
            const SizedBox(height: 8),
            _bar(context, 'Female', profile.female!, maxAbs),
            _bar(context, 'Male', profile.male!, maxAbs),
          ],
          const SizedBox(height: 4),
          Text('Aggregate affinity, not a census of any person.', style: Fonts.monoW(10.5, color: c.faint)),
        ],
      ),
    );
  }

  Widget _bar(BuildContext context, String label, double value, double maxAbs) {
    final c = context.c;
    final frac = (value.abs() / maxAbs).clamp(0.0, 1.0);
    final positive = value >= 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(width: 56, child: Text(label, style: Fonts.monoW(11.5, color: c.muted))),
          Expanded(
            child: LayoutBuilder(builder: (context, box) {
              final half = box.maxWidth / 2;
              return SizedBox(
                height: 16,
                child: Stack(
                  children: [
                    Positioned(left: half - 0.5, top: 0, bottom: 0, child: Container(width: 1, color: c.line)),
                    Positioned(
                      left: positive ? half : half - half * frac,
                      top: 2,
                      bottom: 2,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: half * frac),
                        duration: const Duration(milliseconds: 600),
                        curve: Curves.easeOutCubic,
                        builder: (context, w, _) => Container(
                          width: w,
                          decoration: BoxDecoration(
                            color: positive ? c.accent : c.faint.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
          SizedBox(
            width: 44,
            child: Text('${value >= 0 ? '+' : ''}${(value * 100).round()}',
                textAlign: TextAlign.right, style: Fonts.monoW(11.5, weight: FontWeight.w600, color: positive ? c.ink : c.faint)),
          ),
        ],
      ),
    );
  }
}

class _Markets extends StatelessWidget {
  const _Markets({required this.kit});

  final CompKit kit;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Where they cluster', style: context.t.titleMedium),
          const SizedBox(height: 4),
          Text('${kit.brief.marketInfo.name}, from Qloo\'s affinity heatmap. Hidden gems: fans far ahead of the local market.',
              style: context.t.bodySmall),
          const SizedBox(height: 12),
          for (var i = 0; i < kit.markets.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  SizedBox(width: 22, child: Text('${i + 1}', style: Fonts.monoW(11.5, color: c.faint))),
                  Expanded(child: Text(kit.markets[i].name, style: Fonts.sansW(15, FontWeight.w600, color: c.ink))),
                  switch (kit.markets[i].label) {
                    'hidden_gem' => Pill('Hidden gem', color: c.gold, icon: Icons.diamond_outlined),
                    'stronghold' => Pill('Stronghold', color: c.teal),
                    _ => Pill('Emerging', color: c.muted),
                  },
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 64,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: kit.markets[i].affinity.clamp(0, 1),
                        minHeight: 6,
                        backgroundColor: c.line,
                        color: c.accent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// What the same audience reads, watches, plays and listens to - and where
/// to reach them.
class BeyondSection extends StatelessWidget {
  const BeyondSection({super.key, required this.kit, required this.scans, required this.eyebrow, required this.title, this.subtitle});

  final CompKit kit;
  final List<DomainScan> scans;
  final String eyebrow;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(eyebrow: eyebrow, title: title, subtitle: subtitle),
        for (final scan in scans.where((s) => s.items.isNotEmpty))
          Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(kindIcon(scan.kind), size: 16, color: c.muted),
                  const SizedBox(width: 8),
                  Text(
                    scan.role == 'channel'
                        ? scan.kind.plural
                        : 'They also ${scan.kind.consumeVerb}',
                    style: context.t.titleMedium,
                  ),
                  const SizedBox(width: 8),
                  Text(scan.role == 'channel' ? '' : scan.kind.plural.toLowerCase(), style: context.t.bodySmall),
                ]),
                const SizedBox(height: 10),
                SizedBox(
                  height: 196,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: scan.items.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (context, i) {
                      final cand = scan.items[i];
                      return SizedBox(
                        width: 110,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Cover(entity: cand.entity, width: 110, height: 140, radius: 8),
                            const SizedBox(height: 6),
                            Text(cand.entity.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: Fonts.sansW(13, FontWeight.w600, color: c.ink, height: 1.2)),
                            const SizedBox(height: 2),
                            Text(topPercentLabel(cand.entity.popularity), style: Fonts.monoW(10.5, color: c.faint)),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
