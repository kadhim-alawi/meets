import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:meets_core/meets_core.dart';

import '../../theme.dart';
import '../common.dart';

/// One comp: cover, title, and Meets' reading of the Qloo numbers.
class CompCard extends StatelessWidget {
  const CompCard({super.key, required this.candidate, this.highlight = false});

  final Candidate candidate;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final e = candidate.entity;
    final meta = [if (e.year != null) '${e.year}', if (e.creator != null) e.creator!].join(' · ');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: highlight ? c.accent : c.line, width: highlight ? 1.6 : 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Cover(entity: e, width: 64, height: 94),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: Fonts.display(21, color: c.ink, height: 1.05)),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.t.bodySmall),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FitMeter(fit: candidate.fit),
                    Pill(
                      '${candidate.size.label} · ${topPercentLabel(e.popularity)}',
                      color: sizeColor(context, candidate.size),
                      tooltip: 'Qloo popularity percentile across every ${e.kind.label.toLowerCase()} it tracks',
                    ),
                    if (candidate.isSweetSpot) Pill('Sweet spot', color: c.teal, icon: Icons.check_rounded),
                    for (final f in candidate.flags.where((f) => f != 'weak_fit')) Pill(flagLabel(f), color: c.danger),
                  ],
                ),
                if (candidate.because.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(text: 'Pulled up by ', style: context.t.bodySmall),
                      TextSpan(text: candidate.because.take(2).join(' + '), style: context.t.bodySmall?.copyWith(color: c.ink, fontWeight: FontWeight.w600)),
                    ]),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Fit (up) against size (left = bigger), with the creator's target size band
/// shaded. Makes "right-sized" visible at a glance.
class SweetSpotChart extends StatefulWidget {
  const SweetSpotChart({super.key, required this.items, required this.size, this.pairIds = const {}});

  final List<Candidate> items;
  final SizePref size;
  final Set<String> pairIds;

  @override
  State<SweetSpotChart> createState() => _SweetSpotChartState();
}

class _SweetSpotChartState extends State<SweetSpotChart> {
  int? _hover;

  // x axis: log10(top%) from 0.005% to 40%.
  static const _minLog = -2.3, _maxLog = 1.6;

  static double xOf(double? popularity) {
    final top = ((1 - (popularity ?? 0.9)) * 100).clamp(0.005, 40.0);
    return ((math.log(top) / math.ln10) - _minLog) / (_maxLog - _minLog);
  }

  static double bandX(double topPercent) => ((math.log(topPercent) / math.ln10) - _minLog) / (_maxLog - _minLog);

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final points = widget.items.where((i) => i.entity.popularity != null).toList();
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      const h = 260.0;
      const pad = EdgeInsets.fromLTRB(36, 14, 14, 34);
      final plotW = w - pad.horizontal;
      const plotH = h - 48;
      Offset pos(Candidate cnd) => Offset(pad.left + xOf(cnd.entity.popularity) * plotW, pad.top + (1 - cnd.fit) * plotH);
      return SizedBox(
        height: h,
        child: MouseRegion(
          onHover: (ev) {
            int? best;
            var bestD = 18.0;
            for (var i = 0; i < points.length; i++) {
              final d = (pos(points[i]) - ev.localPosition).distance;
              if (d < bestD) {
                bestD = d;
                best = i;
              }
            }
            if (best != _hover) setState(() => _hover = best);
          },
          onExit: (_) => setState(() => _hover = null),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _ChartPainter(
                    colors: c,
                    targets: targetBands(widget.size),
                    points: [for (final p in points) (pos(p), p, widget.pairIds.contains(p.entity.id))],
                    pad: pad,
                    hover: _hover == null ? null : points[_hover!],
                  ),
                ),
              ),
              for (final p in points.where((p) => widget.pairIds.contains(p.entity.id) || p == (_hover == null ? null : points[_hover!])))
                Positioned(
                  left: (pos(p).dx + 9).clamp(0, w - 170),
                  top: pos(p).dy - 9,
                  child: IgnorePointer(
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 170),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: c.surface.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(4)),
                      child: Text(p.entity.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Fonts.sansW(12, FontWeight.w600, color: c.ink)),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({required this.colors, required this.targets, required this.points, required this.pad, this.hover});

  final MeetsColors colors;
  final List<SizeBand> targets;
  final List<(Offset, Candidate, bool)> points;
  final EdgeInsets pad;
  final Candidate? hover;

  static const _bandEdges = {
    SizeBand.blockbuster: (0.005, 0.1),
    SizeBand.breakout: (0.1, 1.0),
    SizeBand.midlist: (1.0, 5.0),
    SizeBand.niche: (5.0, 20.0),
    SizeBand.deepCut: (20.0, 40.0),
  };

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTRB(pad.left, pad.top, size.width - pad.right, size.height - pad.bottom);
    final grid = Paint()
      ..color = colors.line
      ..strokeWidth = 1;
    // Target band shading.
    for (final band in targets) {
      final edges = _bandEdges[band];
      if (edges == null) continue;
      final x1 = plot.left + _SweetSpotChartState.bandX(edges.$1) * plot.width;
      final x2 = plot.left + _SweetSpotChartState.bandX(edges.$2) * plot.width;
      canvas.drawRect(Rect.fromLTRB(x1, plot.top, x2, plot.bottom), Paint()..color = colors.teal.withValues(alpha: 0.08));
    }
    // Band dividers + labels.
    final labels = <(double, String)>[];
    for (final entry in _bandEdges.entries) {
      final x = plot.left + _SweetSpotChartState.bandX(entry.value.$1) * plot.width;
      if (entry.key != SizeBand.blockbuster) canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), grid);
      final mid = plot.left +
          (_SweetSpotChartState.bandX(entry.value.$1) + _SweetSpotChartState.bandX(entry.value.$2)) / 2 * plot.width;
      labels.add((mid, entry.key.label));
    }
    // Skip labels that would collide on narrow screens.
    var lastRight = double.negativeInfinity;
    for (final (x, label) in labels) {
      final w = _measure(label);
      if (x - w / 2 < lastRight + 6) continue;
      _text(canvas, label, Offset(x, plot.bottom + 8), colors.faint, center: true);
      lastRight = x + w / 2;
    }
    // Fit gridlines.
    for (final f in [0.25, 0.5, 0.75, 1.0]) {
      final y = plot.top + (1 - f) * plot.height;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid..color = colors.line.withValues(alpha: f == 0.5 ? 1 : 0.5));
      _text(canvas, '${(f * 100).round()}', Offset(plot.left - 8, y - 7), colors.faint, right: true);
    }
    // Points.
    for (final (o, cnd, paired) in points) {
      final good = cnd.isSweetSpot;
      final color = paired ? colors.accent : (good ? colors.teal : colors.faint);
      final r = paired ? 7.0 : (cnd == hover ? 6.5 : 5.0);
      canvas.drawCircle(o, r + 2, Paint()..color = colors.surface);
      canvas.drawCircle(o, r, Paint()..color = color);
    }
  }

  double _measure(String s) =>
      (TextPainter(text: TextSpan(text: s, style: Fonts.monoW(10.5)), textDirection: TextDirection.ltr)..layout()).width;

  void _text(Canvas canvas, String s, Offset at, Color color, {bool center = false, bool right = false}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: Fonts.monoW(10.5, color: color)),
      textDirection: TextDirection.ltr,
    )..layout();
    var dx = at.dx;
    if (center) dx -= tp.width / 2;
    if (right) dx -= tp.width;
    tp.paint(canvas, Offset(dx, at.dy));
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) => old.points != points || old.hover != hover || old.colors != colors;
}

/// The primary comps: chart plus a grid of cards.
class CompsSection extends StatefulWidget {
  const CompsSection({super.key, required this.kit});

  final CompKit kit;

  @override
  State<CompsSection> createState() => _CompsSectionState();
}

class _CompsSectionState extends State<CompsSection> {
  bool _sweetOnly = false;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final kit = widget.kit;
    final ranked = rankForDisplay(kit.primary.items);
    final sweet = ranked.where((x) => x.isSweetSpot).toList();
    final shown = (_sweetOnly ? sweet : ranked).take(_all ? 24 : 8).toList();
    final pairIds = {if (kit.pairing != null) kit.pairing!.a.entity.id, if (kit.pairing != null) kit.pairing!.b.entity.id};
    final cols = context.width >= 900 ? 2 : 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          eyebrow: '${kit.brief.format.primary.plural} · ${sweet.length} in your sweet spot',
          title: 'Your comps',
          subtitle: 'Ranked by how strongly people who love your touchstones love them, sized against everything Qloo tracks.',
        ),
        Panel(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Fit vs. size', style: context.t.titleMedium),
                  ),
                  _legendDot(c.accent, 'Comp line'),
                  const SizedBox(width: 12),
                  _legendDot(c.teal, 'Sweet spot'),
                  const SizedBox(width: 12),
                  _legendDot(c.faint, 'Flagged'),
                ],
              ),
              const SizedBox(height: 4),
              Text('Shaded: the ${kit.brief.size.label.toLowerCase()} range you asked for. Left is bigger.', style: context.t.bodySmall),
              const SizedBox(height: 10),
              SweetSpotChart(items: kit.primary.items, size: kit.brief.size, pairIds: pairIds),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (kit.primary.filters.isNotEmpty || kit.primary.notes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final f in kit.primary.filters) Pill(f, icon: Icons.filter_alt_outlined, color: c.ink),
                for (final n in kit.primary.notes) Pill(n, icon: Icons.alt_route_rounded, color: c.accent),
              ],
            ),
          ),
        Row(
          children: [
            FilterChip(
              label: const Text('Sweet spot only'),
              selected: _sweetOnly,
              onSelected: (v) => setState(() => _sweetOnly = v),
            ),
            const Spacer(),
            Text('${shown.length} of ${(_sweetOnly ? sweet : ranked).length}', style: Fonts.monoW(11.5, color: c.faint)),
          ],
        ),
        const SizedBox(height: 12),
        _Grid(
          columns: cols,
          children: [for (final cand in shown) CompCard(candidate: cand, highlight: pairIds.contains(cand.entity.id))],
        ),
        if ((_sweetOnly ? sweet : ranked).length > 8)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: TextButton.icon(
              onPressed: () => setState(() => _all = !_all),
              icon: Icon(_all ? Icons.expand_less_rounded : Icons.expand_more_rounded),
              label: Text(_all ? 'Show fewer' : 'Show all ${(_sweetOnly ? sweet : ranked).length}'),
            ),
          ),
      ],
    );
  }

  Widget _legendDot(Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(label, style: Fonts.monoW(10.5, color: context.c.muted)),
        ],
      );
}

/// Simple responsive grid with equal-height rows.
class _Grid extends StatelessWidget {
  const _Grid({required this.columns, required this.children});

  final int columns;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += columns) {
      final slice = children.sublist(i, math.min(i + columns, children.length));
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var j = 0; j < columns; j++) ...[
                if (j > 0) const SizedBox(width: 12),
                Expanded(child: j < slice.length ? slice[j] : const SizedBox()),
              ],
            ],
          ),
        ),
      ));
    }
    return Column(children: rows);
  }
}
