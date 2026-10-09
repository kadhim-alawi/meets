import 'package:flutter/material.dart';
import 'package:meets_core/meets_core.dart';

import '../../theme.dart';
import '../common.dart';

/// Top of the kit: the "A meets B" line with both covers, then the framing.
class KitHero extends StatelessWidget {
  const KitHero({super.key, required this.kit, required this.actions});

  final CompKit kit;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final b = kit.brief;
    final pair = kit.pairing;
    final phone = context.isPhone;
    final eyebrow = [
      b.format.label,
      if (b.title.isNotEmpty) b.title,
      b.marketInfo.name,
      if (kit.version > 1) 'v${kit.version}',
    ].join('  ·  ');

    final line = pair == null
        ? Text(kit.headline ?? 'Your comp kit', style: phone ? context.t.displaySmall : context.t.displayMedium)
        : Text.rich(
            TextSpan(children: [
              TextSpan(text: pair.a.entity.name),
              TextSpan(text: '  meets  ', style: Fonts.display(phone ? 30 : 46, color: c.accent, italic: true)),
              TextSpan(text: pair.b.entity.name),
            ]),
            style: Fonts.display(phone ? 34 : 56, color: c.ink, height: 1.04),
          );

    final covers = pair == null
        ? const SizedBox.shrink()
        : SizedBox(
            width: phone ? 150 : 230,
            height: phone ? 130 : 200,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  child: Transform.rotate(
                    angle: -0.06,
                    child: _shadowed(Cover(entity: pair.a.entity, width: phone ? 82 : 128, height: phone ? 118 : 184, radius: 10)),
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Transform.rotate(
                    angle: 0.07,
                    child: _shadowed(Cover(entity: pair.b.entity, width: phone ? 82 : 128, height: phone ? 118 : 184, radius: 10)),
                  ),
                ),
              ],
            ),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(eyebrow.toUpperCase(), style: Fonts.monoW(11.5, weight: FontWeight.w600, color: c.muted, spacing: 1.4)),
        const SizedBox(height: 16),
        if (phone) ...[
          covers,
          const SizedBox(height: 18),
          line,
        ] else
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: line),
              const SizedBox(width: 28),
              covers,
            ],
          ),
        if (pair?.why != null) ...[
          const SizedBox(height: 14),
          Text(pair!.why!, style: context.t.bodyLarge?.copyWith(color: c.muted)),
        ],
        const SizedBox(height: 22),
        if (kit.headline != null && pair != null)
          Text(kit.headline!, style: Fonts.display(phone ? 22 : 26, color: c.ink, italic: true, height: 1.2)),
        if (kit.summary != null) ...[
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Text(kit.summary!, style: context.t.bodyLarge),
          ),
        ],
        const SizedBox(height: 20),
        Wrap(spacing: 10, runSpacing: 10, children: actions),
        const SizedBox(height: 18),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Text('Touchstones', style: Fonts.monoW(11.5, color: c.faint, spacing: 0.6)),
            for (final a in kit.anchors)
              Pill(
                a.name,
                icon: kindIcon(a.kind),
                color: kit.brief.anchors.any((x) => x.suggested && x.name.toLowerCase() == a.name.toLowerCase()) ? c.gold : c.ink,
                tooltip: kit.brief.anchors.any((x) => x.suggested && x.name.toLowerCase() == a.name.toLowerCase())
                    ? 'Suggested by the agent from your logline, then verified in Qloo'
                    : 'Your touchstone, resolved in Qloo',
              ),
            for (final t in kit.themes) Pill(t.name, icon: Icons.local_offer_outlined, color: c.teal, tooltip: 'Theme matched to a Qloo tag'),
          ],
        ),
      ],
    );
  }

  Widget _shadowed(Widget child) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.22), blurRadius: 22, offset: const Offset(0, 10))],
        ),
        child: child,
      );
}
