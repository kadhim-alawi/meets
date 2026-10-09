import 'package:meets_core/meets_core.dart';

import '../llm/anthropic.dart';
import 'emitter.dart';

/// How a refinement message changes the brief.
class Refinement {
  const Refinement({required this.brief, this.copyOnly = false, this.copyInstructions, this.changes = const []});

  final Brief brief;

  /// True when only the copy should be rewritten (no new Qloo scans).
  final bool copyOnly;
  final String? copyInstructions;

  /// Human-readable list of what changed.
  final List<String> changes;
}

const _refineSystem = '''
You turn a creator's follow-up request about their comp kit into precise changes. Meets will re-run Qloo with the new settings.

Use update_brief exactly once. Only set the fields the request actually asks to change. If the request is only about wording or tone of the copy (not which comps), set copy_only to true and put the request in copy_instructions.''';

final _updateBrief = toolDef(
  'update_brief',
  'Apply the creator\'s request to the brief.',
  {
    'add_touchstones': {
      'type': 'array',
      'items': {
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
          'kind': {
            'type': 'string',
            'enum': ['book', 'movie', 'tvShow', 'artist', 'videoGame', 'podcast', 'person'],
          },
        },
        'required': ['name'],
      },
    },
    'remove_touchstones': {'type': 'array', 'items': {'type': 'string'}, 'description': 'Touchstone names to remove.'},
    'add_themes': {'type': 'array', 'items': {'type': 'string'}},
    'remove_themes': {'type': 'array', 'items': {'type': 'string'}},
    'exclude_aliases': {'type': 'array', 'items': {'type': 'string'}, 'description': 'Aliases of comps to drop, from the list given.'},
    'recency_years': {'type': 'integer', 'description': '0 for any year.'},
    'size': {'type': 'string', 'enum': ['indie', 'breakout', 'mainstream']},
    'market': {'type': 'string', 'description': 'Market code: ${Market.all.map((m) => m.code).join(', ')}'},
    'ages': {
      'type': 'array',
      'items': {'type': 'string', 'enum': AgeBand.values.map((a) => a.key).toList()},
    },
    'copy_only': {'type': 'boolean'},
    'copy_instructions': {'type': 'string', 'description': 'Instructions for rewriting the copy, if any.'},
  },
);

class Refiner {
  Refiner(this.llm);

  final LlmClient? llm;

  Future<Refinement> refine(CompKit kit, String message, Emitter emit) async {
    final model = llm;
    if (model == null) return heuristic(kit, message);
    final aliases = <String, String>{};
    final lines = <String>[];
    for (final c in kit.primary.items.take(16)) {
      final alias = 'C${aliases.length + 1}';
      aliases[alias] = c.entity.id;
      lines.add('$alias ${c.entity.name}');
    }
    final b = kit.brief;
    final prompt = '''
Current brief: format ${b.format.label}; touchstones ${b.anchors.map((a) => a.name).join(', ')}; themes ${b.themes.isEmpty ? 'none' : b.themes.join(', ')}; recency ${b.recencyYears} years; size ${b.size.name}; market ${b.market}; ages ${b.ages.isEmpty ? 'any' : b.ages.map((a) => a.key).join(', ')}.
Current comps: ${lines.join('; ')}

Creator's request: "$message"''';
    emit.llm('Asked the model to interpret your request', data: {'call': true, 'model': model.model});
    try {
      final response = await model.create(
        system: _refineSystem,
        messages: [
          {'role': 'user', 'content': prompt},
        ],
        tools: [_updateBrief],
        maxTokens: 3000,
        effortOverride: 'low',
      );
      final input = response.toolUses.where((t) => t.name == 'update_brief').map((t) => t.input).firstOrNull ??
          extractJsonObject(response.text);
      if (input == null) return heuristic(kit, message);
      return _apply(kit, input, aliases, message);
    } on LlmException catch (e) {
      emit.warn('The model could not interpret the request; using simple rules', e.message);
      return heuristic(kit, message);
    }
  }

  Refinement _apply(CompKit kit, Json input, Map<String, String> aliases, String message) {
    var b = kit.brief;
    final changes = <String>[];
    final remove = stringsOf(input['remove_touchstones']).map((s) => s.toLowerCase().trim()).toSet();
    var anchors = b.anchors.where((a) => !remove.contains(a.name.toLowerCase().trim())).toList();
    if (anchors.length != b.anchors.length) changes.add('Removed ${b.anchors.length - anchors.length} touchstone(s)');
    for (final item in asList(input['add_touchstones'])) {
      final json = asJson(item);
      final name = asString(json['name'])?.trim();
      if (name == null || name.isEmpty || anchors.any((a) => a.name.toLowerCase() == name.toLowerCase())) continue;
      final kind = EntityKind.fromName(asString(json['kind']));
      anchors.add(AnchorInput(name: name, kind: kind == EntityKind.unknown ? null : kind));
      changes.add('Added touchstone "$name"');
    }
    if (anchors.length > 8) anchors = anchors.sublist(anchors.length - 8);
    final removeThemes = stringsOf(input['remove_themes']).map((s) => s.toLowerCase()).toSet();
    final themes = [
      ...b.themes.where((t) => !removeThemes.contains(t.toLowerCase())),
      ...stringsOf(input['add_themes']).where((t) => !b.themes.contains(t)),
    ].take(8).toList();
    if (themes.join('|') != b.themes.join('|')) changes.add('Themes: ${themes.isEmpty ? 'none' : themes.join(', ')}');
    final exclude = [...b.excludeIds, ...stringsOf(input['exclude_aliases']).map((a) => aliases[a.toUpperCase()]).whereType<String>()];
    if (exclude.length != b.excludeIds.length) changes.add('Dropped ${exclude.length - b.excludeIds.length} comp(s)');
    final recency = asInt(input['recency_years']);
    if (recency != null && recency != b.recencyYears && recency >= 0 && recency <= 50) {
      changes.add(recency == 0 ? 'Any year' : 'Last $recency years');
    }
    final sizeName = asString(input['size'])?.trim().toLowerCase();
    final size = SizePref.values.where((v) => v.name == sizeName).firstOrNull;
    if (size != null && size != b.size) changes.add('Size: ${size.label}');
    final marketCode = asString(input['market'])?.toUpperCase();
    final market = marketCode != null && Market.all.any((m) => m.code == marketCode) ? marketCode : null;
    if (market != null && market != b.market) changes.add('Market: ${Market.fromCode(market).name}');
    final ages = input['ages'] == null ? null : stringsOf(input['ages']).map(AgeBand.fromKey).whereType<AgeBand>().toList();
    if (ages != null && ages.map((a) => a.key).join() != b.ages.map((a) => a.key).join()) {
      changes.add(ages.isEmpty ? 'Any age' : 'Ages ${ages.map((a) => a.label).join(', ')}');
    }
    b = b.copyWith(
      anchors: anchors,
      themes: themes,
      excludeIds: exclude,
      recencyYears: recency != null && recency >= 0 && recency <= 50 ? recency : null,
      size: size,
      market: market,
      ages: ages,
    );
    final copyInstructions = asString(input['copy_instructions'])?.trim();
    // Wording-only requests rewrite the copy even if the model forgot copy_only.
    final copyOnly = changes.isEmpty && (asBool(input['copy_only']) || (copyInstructions != null && copyInstructions.isNotEmpty));
    final instructions = (copyInstructions == null || copyInstructions.isEmpty) ? (copyOnly ? message : null) : copyInstructions;
    if (copyOnly) changes.add('Rewrote the copy');
    return Refinement(brief: b, copyOnly: copyOnly, copyInstructions: instructions, changes: changes);
  }

  /// Rules for when no language model is configured.
  static Refinement heuristic(CompKit kit, String message) {
    final text = message.toLowerCase();
    var b = kit.brief;
    final changes = <String>[];
    final years = RegExp(r'(?:last|past|within)\s+(\d{1,2})\s+years?').firstMatch(text);
    if (years != null) {
      final n = int.parse(years.group(1)!).clamp(1, 50);
      b = b.copyWith(recencyYears: n);
      changes.add('Last $n years');
    } else if (text.contains('any year') || text.contains('classics')) {
      b = b.copyWith(recencyYears: 0);
      changes.add('Any year');
    }
    if (RegExp(r'\b(indie|smaller|niche|lesser[- ]known|underground)\b').hasMatch(text)) {
      b = b.copyWith(size: SizePref.indie);
      changes.add('Size: Indie');
    } else if (RegExp(r'\b(mainstream|bigger|popular|blockbuster)\b').hasMatch(text)) {
      b = b.copyWith(size: SizePref.mainstream);
      changes.add('Size: Mainstream');
    }
    String? market;
    for (final m in Market.all) {
      if (m.code != 'GLOBAL' && text.contains(m.name.toLowerCase())) {
        market = m.code;
        break;
      }
    }
    if (market == null && RegExp(r'\b(uk|britain|british)\b').hasMatch(text)) market = 'GB';
    if (market == null && RegExp(r'\b(usa|us market|america|american)\b').hasMatch(text)) market = 'US';
    if (market != null && market != b.market) {
      b = b.copyWith(market: market);
      changes.add('Market: ${Market.fromCode(market).name}');
    }
    final more = RegExp(r'more like ([^,.;]+)').firstMatch(message);
    if (more != null) {
      final name = more.group(1)!.trim();
      b = b.copyWith(anchors: [...b.anchors, AnchorInput(name: name)]);
      changes.add('Added touchstone "$name"');
    }
    // Match known comp names (titles can contain commas, so no regex capture).
    for (final c in kit.primary.items) {
      final name = c.entity.name.toLowerCase();
      final asked = ['drop ', 'remove ', 'without ', 'no '].any((verb) => text.contains('$verb$name'));
      if (asked && !b.excludeIds.contains(c.entity.id)) {
        b = b.copyWith(excludeIds: [...b.excludeIds, c.entity.id]);
        changes.add('Dropped "${c.entity.name}"');
      }
    }
    return Refinement(brief: b, changes: changes);
  }
}
