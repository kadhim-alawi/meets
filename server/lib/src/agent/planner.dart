import 'package:meets_core/meets_core.dart';

import '../llm/anthropic.dart';
import 'emitter.dart';

/// What the intake step proposes. Every touchstone is only a *search
/// candidate*: it is dropped unless Qloo resolves it.
class PlanResult {
  const PlanResult({this.touchstones = const [], this.themes = const [], this.reading});

  final List<AnchorInput> touchstones;
  final List<String> themes;
  final String? reading;
}

const _kindNames = ['book', 'movie', 'tvShow', 'artist', 'videoGame', 'podcast', 'person'];

const plannerSystem = '''
You are the intake step of Meets, an agent that finds comparable titles ("comps") and the first audience for a creative work, using Qloo's taste graph.

Your only job is to turn a creator's brief into good search inputs. Qloo does all measuring and ranking afterwards; you never claim facts about audiences or sales.

Touchstones are existing, real, findable works, artists or people that the project's audience would also love. Prefer specific, well-catalogued titles over vague genres. Use exact official titles. Mix in at most one touchstone from another category when it sharpens the audience (a film for a novel, a novelist for a band). Never repeat a touchstone the creator already gave.

Themes are 1-3 word descriptors in the style of genre and keyword tags: "found family", "dark academia", "heist", "cozy fantasy", "synthwave", "workplace comedy". No sentences.

Always finish by calling submit_plan exactly once.''';

final _submitPlan = toolDef(
  'submit_plan',
  'Submit the search inputs for this brief.',
  {
    'touchstones': {
      'type': 'array',
      'description': 'Additional touchstones to search for in Qloo.',
      'items': {
        'type': 'object',
        'properties': {
          'name': {'type': 'string', 'description': 'Exact title or name.'},
          'kind': {'type': 'string', 'enum': _kindNames},
          'reason': {'type': 'string', 'description': 'Why this audience overlaps, in under 15 words.'},
        },
        'required': ['name', 'kind'],
      },
    },
    'themes': {
      'type': 'array',
      'items': {'type': 'string'},
      'description': 'Up to 4 short theme or genre descriptors.',
    },
    'reading': {'type': 'string', 'description': 'One sentence: what this project is, in market terms.'},
  },
  required: ['touchstones', 'themes', 'reading'],
);

class Planner {
  Planner(this.llm);

  final LlmClient llm;

  /// How many extra touchstones to ask for, given what the creator supplied.
  static int wanted(Brief brief) => switch (brief.anchors.length) { 0 => 4, 1 => 3, 2 => 2, _ => 0 };

  Future<PlanResult> plan(Brief brief, Emitter emit) async {
    final want = wanted(brief);
    final themesWanted = brief.themes.isEmpty ? 4 : 0;
    final given = brief.anchors.map((a) => '- ${a.name}${a.kind == null ? '' : ' (${a.kind!.label})'}').join('\n');
    final prompt = '''
Format: ${brief.format.label} (comps come from Qloo's ${brief.format.primary.plural.toLowerCase()} category)
Title: ${brief.title.isEmpty ? '(untitled)' : brief.title}
Logline / description: ${brief.logline}
Creator's touchstones:
${given.isEmpty ? '(none yet)' : given}
Creator's themes: ${brief.themes.isEmpty ? '(none)' : brief.themes.join(', ')}

Propose $want additional touchstone${want == 1 ? '' : 's'} (mostly ${brief.format.primary.plural.toLowerCase()}) and $themesWanted theme${themesWanted == 1 ? '' : 's'}.''';

    emit.llm('Asked the model to read the brief', data: {'call': true, 'model': llm.model});
    final response = await llm.create(
      system: plannerSystem,
      messages: [
        {'role': 'user', 'content': prompt},
      ],
      tools: [_submitPlan],
      maxTokens: 4000,
      effortOverride: 'low',
    );
    final input = response.toolUses.where((t) => t.name == 'submit_plan').map((t) => t.input).firstOrNull ??
        extractJsonObject(response.text) ??
        const <String, dynamic>{};

    final existing = brief.anchors.map((a) => a.name.toLowerCase().trim()).toSet();
    final touchstones = <AnchorInput>[];
    for (final item in asList(input['touchstones'])) {
      final json = asJson(item);
      final name = asString(json['name'])?.trim();
      if (name == null || name.isEmpty || existing.contains(name.toLowerCase())) continue;
      final kind = EntityKind.fromName(asString(json['kind']));
      touchstones.add(AnchorInput(name: name, kind: kind == EntityKind.unknown ? null : kind, suggested: true));
      existing.add(name.toLowerCase());
      if (touchstones.length >= want) break;
    }
    final themes = stringsOf(input['themes'])
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty && t.length <= 40)
        .take(themesWanted)
        .toList();
    return PlanResult(touchstones: touchstones, themes: themes, reading: asString(input['reading']));
  }
}
