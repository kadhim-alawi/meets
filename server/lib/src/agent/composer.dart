import 'package:meets_core/meets_core.dart';

/// Writes pitch copy and targeting lists straight from the evidence, with no
/// language model. Used when no LLM key is configured and as the fallback
/// whenever the model fails or its draft does not pass validation.
class Composer {
  const Composer();

  /// "Piranesi (Susanna Clarke, 2020)".
  static String cite(Entity e, {bool creator = true, bool year = true}) {
    final extras = [
      if (creator && e.creator != null) e.creator!,
      if (year && e.year != null) '${e.year}',
    ];
    return extras.isEmpty ? e.name : '${e.name} (${extras.join(', ')})';
  }

  static String joinNames(List<String> names, {String last = 'and'}) {
    if (names.isEmpty) return '';
    if (names.length == 1) return names.first;
    return '${names.take(names.length - 1).join(', ')} $last ${names.last}';
  }

  static List<Candidate> sweetSpots(DomainScan scan, {int take = 6}) {
    final ranked = rankForDisplay(scan.items);
    final sweet = ranked.where((c) => c.isSweetSpot).toList();
    return (sweet.length >= 2 ? sweet : ranked).take(take).toList();
  }

  static DomainScan? scanOf(CompKit kit, EntityKind kind) {
    for (final s in [kit.primary, ...kit.cross, ...kit.channels]) {
      if (s.kind == kind) return s;
    }
    return null;
  }

  String headline(CompKit kit) {
    final f = kit.brief.format;
    final pair = kit.pairing;
    final title = kit.brief.title.isEmpty ? 'Your ${f.noun}' : kit.brief.title;
    if (pair != null) {
      final sweet = sweetSpots(kit.primary).length;
      return '$title sits in a ${kit.brief.size.label.toLowerCase()} lane with $sweet right-sized comps — lead with ${pair.a.entity.name} and ${pair.b.entity.name}.';
    }
    final top = sweetSpots(kit.primary, take: 2).map((c) => c.entity.name).toList();
    return top.isEmpty ? '$title, measured against Qloo\'s taste graph.' : '$title sits next to ${joinNames(top)}.';
  }

  String summary(CompKit kit) {
    final f = kit.brief.format;
    final sweet = sweetSpots(kit.primary);
    final bigs = kit.primary.items.where((c) => c.flags.contains('too_big')).length;
    final parts = <String>[
      'Meets scanned Qloo\'s ${f.primary.plural.toLowerCase()} for people who love ${joinNames(kit.anchors.take(3).map((a) => a.name).toList())}.',
      '${sweet.where((c) => c.isSweetSpot).length} of the top ${kit.primary.items.length} '
          '${sweet.where((c) => c.isSweetSpot).length == 1 ? 'sits' : 'sit'} in your ${kit.brief.size.label.toLowerCase()} sweet spot'
          '${bigs > 0 ? '; $bigs ${bigs == 1 ? 'is' : 'are'} too big to use as comps' : ''}.',
    ];
    final audience = kit.audience;
    if (audience != null && !audience.isEmpty) parts.add(describeAudience(audience, f.audience));
    final gems = kit.markets.where((m) => m.label == 'hidden_gem').map((m) => m.name).toList();
    if (kit.markets.isNotEmpty) {
      parts.add('Strongest markets: ${joinNames(kit.markets.take(3).map((m) => m.name).toList())}'
          '${gems.isEmpty ? '' : ', with ${gems.first} as a hidden gem'}.');
    }
    return parts.join(' ');
  }

  List<CopyBlock> copy(CompKit kit) {
    final f = kit.brief.format;
    final title = kit.brief.title.isEmpty ? '[TITLE]' : kit.brief.title.toUpperCase();
    final sweet = sweetSpots(kit.primary);
    final pair = kit.pairing;
    final a = pair?.a.entity ?? (sweet.isNotEmpty ? sweet[0].entity : null);
    final b = pair?.b.entity ?? (sweet.length > 1 ? sweet[1].entity : null);
    final crossTop = <Entity>[
      for (final scan in kit.cross)
        if (scan.items.isNotEmpty) scan.items.first.entity,
    ];
    final blocks = <CopyBlock>[];
    for (final spec in f.copySpecs) {
      final body = switch (spec.id) {
        'comp_line' => _compLine(kit, a, b),
        'pitch' => _pitch(kit, title, a, b, crossTop),
        'audience' => _audience(kit, crossTop),
        'fans_of' => 'For fans of ${joinNames(sweet.take(4).map((c) => c.entity.name).toList())}.',
        'ad_hooks' => _hooks(kit, sweet, crossTop),
        _ => '',
      };
      if (body.trim().isNotEmpty) {
        blocks.add(CopyBlock(id: spec.id, title: spec.title, hint: spec.hint, body: body.trim(), author: 'template'));
      }
    }
    return blocks;
  }

  String _compLine(CompKit kit, Entity? a, Entity? b) {
    if (a == null) return '';
    if (b == null) return 'For fans of ${a.name}.';
    final why = kit.pairing?.why;
    return '${a.name} meets ${b.name}.${why == null ? '' : '\n\n$why'}';
  }

  String _pitch(CompKit kit, String title, Entity? a, Entity? b, List<Entity> crossTop) {
    final f = kit.brief.format;
    if (a == null) return '';
    final comps = [a, if (b != null) b].map(cite).toList();
    final also = crossTop.take(2).map((e) => e.name).toList();
    final alsoLine = also.isEmpty ? '' : ' Its audience also loves ${joinNames(also)}.';
    return switch (f) {
      WorkFormat.book =>
        '$title, complete at [word count] words, will appeal to readers of ${joinNames(comps)}.$alsoLine',
      WorkFormat.film => 'Comps: ${joinNames(comps)}.$alsoLine The audience: ${_audienceShort(kit)}',
      WorkFormat.tv => 'For viewers of ${joinNames(comps)}.$alsoLine The audience: ${_audienceShort(kit)}',
      WorkFormat.music =>
        'Sounds like ${a.name}${b == null ? '' : ' meets ${b.name}'}. For fans of ${joinNames(Composer.sweetSpots(kit.primary, take: 4).map((c) => c.entity.name).toList())}.$alsoLine',
      WorkFormat.game => 'If you like ${joinNames(comps)}, you\'ll want to wishlist $title.$alsoLine',
      WorkFormat.podcast => 'For listeners of ${joinNames(comps)}.$alsoLine The audience: ${_audienceShort(kit)}',
      WorkFormat.standup => 'For fans of ${joinNames(comps)}.$alsoLine The audience: ${_audienceShort(kit)}',
    };
  }

  String _audienceShort(CompKit kit) {
    final audience = kit.audience;
    if (audience == null || audience.isEmpty) return 'see the audience section.';
    return describeAudience(audience, kit.brief.format.audience).replaceFirst('Your ', '');
  }

  String _audience(CompKit kit, List<Entity> crossTop) {
    final f = kit.brief.format;
    final parts = <String>[];
    final audience = kit.audience;
    if (audience != null && !audience.isEmpty) {
      parts.add(describeAudience(audience, f.audience));
      final descriptors = audience.descriptors.take(4).map((t) => t.name.toLowerCase()).toList();
      if (descriptors.isNotEmpty) parts.add('Their taste over-indexes on ${joinNames(descriptors)}.');
    }
    final byVerb = <String, List<String>>{};
    for (final scan in kit.cross) {
      final names = scan.items.take(2).map((c) => c.entity.name);
      byVerb.putIfAbsent(scan.kind.consumeVerb, () => []).addAll(names);
    }
    final crossLines = [
      for (final e in byVerb.entries.take(3))
        if (e.value.isNotEmpty) '${e.key} ${joinNames(e.value.take(3).toList())}',
    ];
    if (crossLines.isNotEmpty) parts.add('Beyond ${f.primary.plural.toLowerCase()}, they ${joinNames(crossLines)}.');
    if (kit.markets.isNotEmpty) {
      parts.add('They cluster in ${joinNames(kit.markets.take(3).map((m) => m.name).toList())}.');
    }
    return parts.join(' ');
  }

  String _hooks(CompKit kit, List<Candidate> sweet, List<Entity> crossTop) {
    final f = kit.brief.format;
    final lines = <String>[];
    if (sweet.isNotEmpty) lines.add('Finished ${sweet[0].entity.name} and want more? Meet ${kit.brief.title.isEmpty ? 'your next favourite ${f.noun}' : kit.brief.title}.');
    if (sweet.length > 1) lines.add('For ${f.audience} who loved ${sweet[1].entity.name}.');
    if (crossTop.isNotEmpty) lines.add('If ${crossTop.first.name} is your comfort ${crossTop.first.kind.label.toLowerCase()}, this ${f.noun} is for you.');
    return lines.map((l) => '• $l').join('\n');
  }

  /// Ready-to-paste lists for each platform the format cares about.
  List<TargetList> targeting(CompKit kit) {
    final out = <TargetList>[];
    for (final spec in kit.brief.format.targets) {
      final items = <String>[];
      for (final kind in spec.kinds) {
        final scan = scanOf(kit, kind);
        if (scan == null) continue;
        final list = scan.role == 'primary' ? sweetSpots(scan, take: 12) : scan.items.take(8).toList();
        for (final c in list) {
          final e = c.entity;
          final label = switch (spec.id) {
            'amazon' => e.creator == null ? e.name : '${e.name} — ${e.creator}',
            'bookbub' => e.creator ?? e.name,
            _ => e.name,
          };
          if (!items.contains(label)) items.add(label);
        }
      }
      if (items.isNotEmpty) out.add(TargetList(id: spec.id, platform: spec.platform, how: spec.how, items: items.take(15).toList()));
    }
    return out;
  }

  /// Notes every kit carries so nobody mistakes taste data for a forecast.
  List<String> standardNotes(CompKit kit) => [
        'Fit and size come from Qloo affinity and popularity percentiles. They describe aggregate taste, not sales or any individual.',
        '"Top 1%" popularity is still well known: Qloo ranks against every ${kit.brief.format.primary.label.toLowerCase()} it tracks.',
        'Touchstones marked "suggested" were proposed by the agent from your logline and kept only if Qloo found them.',
      ];
}
