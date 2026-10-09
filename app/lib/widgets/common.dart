import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:meets_core/meets_core.dart';

import '../api.dart';
import '../theme.dart';

/// The wordmark: an italic serif "meets" with two overlapping rings.
class MeetsLogo extends StatelessWidget {
  const MeetsLogo({super.key, this.size = 28, this.onTap});

  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final logo = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size * 1.25,
          height: size * 0.85,
          child: CustomPaint(painter: _RingsPainter(c.accent, c.ink)),
        ),
        SizedBox(width: size * 0.28),
        Text('meets', style: Fonts.display(size, color: c.ink, italic: true, height: 1)),
      ],
    );
    if (onTap == null) return logo;
    return Semantics(
      button: true,
      label: 'Meets home',
      child: MouseRegion(cursor: SystemMouseCursors.click, child: GestureDetector(onTap: onTap, child: logo)),
    );
  }
}

class _RingsPainter extends CustomPainter {
  _RingsPainter(this.a, this.b);

  final Color a;
  final Color b;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.height / 2;
    final pa = Paint()
      ..color = a
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.height * 0.13;
    final pb = Paint()
      ..color = b
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.height * 0.13;
    canvas.drawCircle(Offset(r, r), r * 0.84, pa);
    canvas.drawCircle(Offset(size.width - r, r), r * 0.84, pb);
  }

  @override
  bool shouldRepaint(covariant _RingsPainter old) => old.a != a || old.b != b;
}

/// A rounded surface with a hairline border.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(20), this.color, this.radius = 18});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? c.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: c.line),
      ),
      child: child,
    );
  }
}

/// Small rounded label, optionally tinted.
class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, this.color, this.icon, this.filled = false, this.tooltip});

  final String label;
  final Color? color;
  final IconData? icon;
  final bool filled;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tone = color ?? c.muted;
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? tone : tone.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: filled ? null : Border.all(color: tone.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: filled ? c.surface : tone), const SizedBox(width: 4)],
          Flexible(
            child: Text(label, style: Fonts.monoW(11, weight: FontWeight.w600, color: filled ? c.surface : tone, spacing: 0.2)),
          ),
        ],
      ),
    );
    return tooltip == null ? pill : Tooltip(message: tooltip!, child: pill);
  }
}

/// Section title with a mono eyebrow.
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.eyebrow, required this.title, this.subtitle, this.trailing});

  final String eyebrow;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(eyebrow.toUpperCase(), style: Fonts.monoW(11.5, weight: FontWeight.w600, color: c.accent, spacing: 1.4)),
                const SizedBox(height: 6),
                Text(title, style: context.t.headlineMedium),
                if (subtitle != null) ...[
                  const SizedBox(height: 6),
                  Text(subtitle!, style: context.t.bodyMedium?.copyWith(color: c.muted)),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

IconData kindIcon(EntityKind kind) => switch (kind) {
      EntityKind.book => Icons.menu_book_rounded,
      EntityKind.movie => Icons.movie_outlined,
      EntityKind.tvShow => Icons.tv_rounded,
      EntityKind.artist => Icons.graphic_eq_rounded,
      EntityKind.videoGame => Icons.sports_esports_outlined,
      EntityKind.podcast => Icons.podcasts_rounded,
      EntityKind.person => Icons.mic_external_on_outlined,
      EntityKind.brand => Icons.sell_outlined,
      EntityKind.place => Icons.place_outlined,
      EntityKind.destination => Icons.public,
      EntityKind.unknown => Icons.circle_outlined,
    };

IconData formatIcon(WorkFormat f) => switch (f) {
      WorkFormat.book => Icons.menu_book_rounded,
      WorkFormat.film => Icons.movie_outlined,
      WorkFormat.tv => Icons.tv_rounded,
      WorkFormat.music => Icons.graphic_eq_rounded,
      WorkFormat.game => Icons.sports_esports_outlined,
      WorkFormat.podcast => Icons.podcasts_rounded,
      WorkFormat.standup => Icons.mic_external_on_outlined,
    };

int _hash(String s) {
  var h = 0;
  for (final u in s.codeUnits) {
    h = (h * 31 + u) & 0x7fffffff;
  }
  return h;
}

/// Cover art through the server's image proxy, or a generated typographic
/// tile when Qloo has no image (or it fails to load).
class Cover extends StatelessWidget {
  const Cover({super.key, required this.entity, this.width = 72, this.height = 104, this.radius = 8});

  final Entity entity;
  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final url = Api.instance.imageUrl(entity.imageUrl);
    final placeholder = _Placeholder(entity: entity, width: width, height: height);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: width,
        height: height,
        child: url == null
            ? placeholder
            : Image.network(
                url,
                fit: BoxFit.cover,
                width: width,
                height: height,
                errorBuilder: (_, _, _) => placeholder,
                frameBuilder: (context, child, frame, sync) => AnimatedOpacity(
                  opacity: frame == null && !sync ? 0 : 1,
                  duration: const Duration(milliseconds: 250),
                  child: frame == null && !sync ? placeholder : child,
                ),
              ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.entity, required this.width, required this.height});

  final Entity entity;
  final double width;
  final double height;

  static const _tones = [
    (Color(0xFF2F4858), Color(0xFFF6E7CB)),
    (Color(0xFF7A3B2E), Color(0xFFF8E9DD)),
    (Color(0xFF1C6B66), Color(0xFFE6F2EF)),
    (Color(0xFF3D3B70), Color(0xFFECEAFB)),
    (Color(0xFF8C6A12), Color(0xFFFBF1D6)),
    (Color(0xFF5B5F2A), Color(0xFFF1F2DE)),
    (Color(0xFF8E3B5C), Color(0xFFFAE6EE)),
    (Color(0xFF26313B), Color(0xFFE9EEF2)),
  ];

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _tones[_hash(entity.name) % _tones.length];
    final small = width < 60;
    return Container(
      color: bg,
      padding: EdgeInsets.all(small ? 5 : 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(kindIcon(entity.kind), size: small ? 11 : 14, color: fg.withValues(alpha: 0.7)),
          const Spacer(),
          Text(
            entity.name,
            maxLines: small ? 3 : 4,
            overflow: TextOverflow.ellipsis,
            style: Fonts.display(small ? 11 : (width > 120 ? 22 : 15), color: fg, height: 1.0),
          ),
        ],
      ),
    );
  }
}

/// Five-segment meter for fit (0..1).
class FitMeter extends StatelessWidget {
  const FitMeter({super.key, required this.fit, this.label = true});

  final double fit;
  final bool label;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final filled = (fit * 5).clamp(0, 5).round();
    final color = fit >= 0.75 ? c.teal : (fit >= 0.5 ? c.ink : c.faint);
    return Tooltip(
      message: 'Fit ${(fit * 100).round()} / 100 — from Qloo affinity rank for your touchstones',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 5; i++)
            Container(
              width: 9,
              height: 9,
              margin: const EdgeInsets.only(right: 2.5),
              decoration: BoxDecoration(
                color: i < filled ? color : c.line,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          if (label) ...[
            const SizedBox(width: 5),
            Text('${(fit * 100).round()}', style: Fonts.monoW(11.5, weight: FontWeight.w600, color: color)),
          ],
        ],
      ),
    );
  }
}

Color sizeColor(BuildContext context, SizeBand band) {
  final c = context.c;
  return switch (band) {
    SizeBand.blockbuster => c.danger,
    SizeBand.breakout => c.accent,
    SizeBand.midlist => c.teal,
    SizeBand.niche => c.gold,
    SizeBand.deepCut => c.muted,
    SizeBand.unknown => c.faint,
  };
}

/// Copies [text] and confirms with a snackbar.
Future<void> copyText(BuildContext context, String text, {String what = 'Copied'}) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(what), duration: const Duration(milliseconds: 1600)));
}

/// Constrains page content to a readable width with consistent gutters.
class PageWidth extends StatelessWidget {
  const PageWidth({super.key, required this.child, this.max = 1180});

  final Widget child;
  final double max;

  @override
  Widget build(BuildContext context) {
    final gutter = context.isPhone ? 16.0 : 28.0;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: max + gutter * 2),
        child: SizedBox(
          width: double.infinity,
          child: Padding(padding: EdgeInsets.symmetric(horizontal: gutter), child: child),
        ),
      ),
    );
  }
}

/// Banner shown on every screen when the server runs on sample data.
class PreviewBanner extends StatelessWidget {
  const PreviewBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      width: double.infinity,
      color: c.gold,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      child: Text(
        'PREVIEW MODE · sample data with placeholder scores, not Qloo results. Set QLOO_API_KEY for live data.',
        textAlign: TextAlign.center,
        style: Fonts.monoW(11.5, weight: FontWeight.w600, color: c.surface, spacing: 0.3),
      ),
    );
  }
}
