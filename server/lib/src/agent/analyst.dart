import 'dart:convert';

import 'package:meets_core/meets_core.dart';

import '../llm/anthropic.dart';
import '../qloo/qloo_client.dart';
import 'emitter.dart';
import 'qloo_service.dart';

/// Short aliases (E1, E2 ...) for entity ids, so prompts stay small and the
/// model cannot cite anything it was not shown.
class AliasBook {
  final _toId = <String, String>{};
  final _toAlias = <String, String>{};
  final Map<String, Entity> entities = {};

  String alias(Entity e) {
    final existing = _toAlias[e.id];
    if (existing != null) return existing;
    final a = 'E${_toId.length + 1}';
    _toId[a] = e.id;
    _toAlias[e.id] = a;
    entities[e.id] = e;
    return a;
  }

  String? idOf(String alias) => _toId[alias.trim().toUpperCase()];
  Entity? entityOf(String alias) {
    final id = idOf(alias);
    return id == null ? null : entities[id];
  }
}

final _refPattern = RegExp(r'\{\{\s*([A-Za-z]\d+)\s*\}\}');

/// Replaces `{{E3}}` with entity names. Unknown aliases are dropped and
/// reported, so copy can only name what Qloo returned.
(String, List<String>) resolveRefs(String text, AliasBook book) {
  final unknown = <String>[];
  final out = text.replaceAllMapped(_refPattern, (m) {
    final e = book.entityOf(m.group(1)!);
    if (e == null) {
      unknown.add(m.group(1)!);
      return '';
    }
    return e.name;
  });
  return (out.replaceAll(RegExp(r'\{\{[^}]*\}\}'), '').replaceAll(RegExp(r' {2,}'), ' ').trim(), unknown);
}

const analystSystem = '''
You are the analyst inside Meets, an agent that helps creators pitch and position their work using Qloo's taste graph (aggregate, privacy-safe affinity data across books, film, TV, music, games, podcasts, people and brands).

You receive an evidence digest that Meets already gathered from Qloo. Your job is to turn it into pitch copy a creator can paste into a query letter, pitch deck, press kit, store page or ad.

Grounding rules - these are absolute:
- Refer to every title, artist, person or brand ONLY with its alias in double braces, e.g. {{E4}}. Never type a title or name yourself. Meets swaps aliases for the real names.
- Only use aliases that appear in the digest or in tool results.
- Never invent numbers. You may quote fit, size ("Top 2%") and age skews exactly as given, or describe them in words.
- Do not claim sales, rankings, awards or facts that are not in the digest.
- Affinity is aggregate taste, not a forecast: never promise results.

Style: plain, specific, confident, no hype words ("captivating", "must-read", "unforgettable"), no exclamation marks, no emoji. Write like a sharp agent or producer, not a marketer. Keep each block tight.

You may call check_fit to test how strongly specific entities fit the creator's touchstones, or compare_audiences to see what two groups of entities share, when it would sharpen a claim. Use at most two tool calls. Then call submit_copy exactly once.''';

final _tools = [
  toolDef(
    'check_fit',
    'Measure how strongly entities fit the creator\'s audience (Qloo affinity to the touchstones). Returns affinity per alias.',
    {
      'aliases': {
        'type': 'array',
        'items': {'type': 'string'},
        'description': 'Aliases from the digest, e.g. ["E4","E9"]. Same category only.',
      },
    },
    required: ['aliases'],
  ),
  toolDef(
    'compare_audiences',
    'Ask Qloo what two groups of entities share (taste tags common to both audiences).',
    {
      'a': {'type': 'array', 'items': {'type': 'string'}, 'description': 'Aliases for group A.'},
      'b': {'type': 'array', 'items': {'type': 'string'}, 'description': 'Aliases for group B.'},
    },
    required: ['a', 'b'],
  ),
  toolDef(
    'submit_copy',
    'Submit the finished pitch kit copy.',
    {
      'headline': {'type': 'string', 'description': 'One sentence framing the project for buyers, using aliases.'},
      'summary': {'type': 'string', 'description': '2-4 sentence strategy summary: where it sits, who it is for, what to lead with.'},
      'pair': {
        'type': 'object',
        'description': 'The two comps for the comp line, from PAIRING OPTIONS (or other primary comps if clearly better).',
        'properties': {
          'a': {'type': 'string'},
          'b': {'type': 'string'},
        },
        'required': ['a', 'b'],
      },
      'blocks': {
        'type': 'array',
        'description': 'One entry per requested copy block id.',
        'items': {
          'type': 'object',
          'properties': {
            'id': {'type': 'string'},
            'body': {'type': 'string'},
          },
          'required': ['id', 'body'],
        },
      },
    },
    required: ['headline', 'summary', 'pair', 'blocks'],
  ),
];

/// Builds the evidence digest the model writes from.
String buildDigest(CompKit kit, AliasBook book) {
  final b = kit.brief;
  final f = b.format;
  final buf = StringBuffer();
  String fmt(double v) => v.toStringAsFixed(2);
  String entityLine(Candidate c) {
    final e = c.entity;
    final parts = <String>[
      '{{${book.alias(e)}}} ${e.name}',
      if (e.year != null) '${e.year}',
      if (e.creator != null) 'by ${e.creator}',
      'fit ${fmt(c.fit)}',
      'size ${c.size.label} (${topPercentLabel(e.popularity)})',
      if (c.recency != null) 'recency ${c.recency!.label}',
      if (c.flags.isNotEmpty) 'flags ${c.flags.map(flagLabel).join('/')}',
      if (c.because.isNotEmpty) 'because ${c.because.join(' + ')}',
      if (e.tags.isNotEmpty) 'tags ${e.tags.take(4).map((t) => t.name.toLowerCase()).join(', ')}',
    ];
    return '- ${parts.join(' · ')}';
  }

  buf.writeln('BRIEF');
  buf.writeln('format: ${f.label} · title: ${b.title.isEmpty ? '(untitled)' : b.title} · market: ${b.marketInfo.name} · '
      'recency window: ${b.recencyYears == 0 ? 'any' : '${b.recencyYears} years'} · size target: ${b.size.label}');
  if (b.logline.isNotEmpty) buf.writeln('logline: ${b.logline}');
  buf.writeln();
  buf.writeln('TOUCHSTONES (resolved in Qloo)');
  for (final a in kit.anchors) {
    buf.writeln('- {{${book.alias(a)}}} ${a.name} (${a.kind.label}${a.year == null ? '' : ', ${a.year}'}${a.creator == null ? '' : ', ${a.creator}'})');
  }
  buf.writeln();
  buf.writeln('PRIMARY COMPS (${f.primary.plural.toLowerCase()}, best first; fit 0-1 from Qloo affinity rank; size from Qloo popularity percentile)');
  for (final c in kit.primary.items.take(14)) {
    buf.writeln(entityLine(c));
  }
  if (kit.primary.filters.isNotEmpty) buf.writeln('filters: ${kit.primary.filters.join('; ')}');
  buf.writeln();
  final pair = kit.pairing;
  if (pair != null) {
    buf.writeln('PAIRING OPTIONS');
    buf.writeln('1. {{${book.alias(pair.a.entity)}}} meets {{${book.alias(pair.b.entity)}}}'
        '${pair.similarity == null ? '' : ' (similarity ${fmt(pair.similarity!)})'}${pair.why == null ? '' : ' - ${pair.why}'}');
    final ledger = kit.ledger;
    var n = 2;
    for (final alt in pair.alternatives) {
      final ea = ledger[alt.first], eb = ledger[alt.last];
      if (ea != null && eb != null) buf.writeln('${n++}. {{${book.alias(ea)}}} meets {{${book.alias(eb)}}}');
    }
    buf.writeln();
  }
  buf.writeln('ALSO LOVED BY THE SAME AUDIENCE');
  for (final scan in [...kit.cross, ...kit.channels]) {
    final names = scan.items.take(6).map((c) => '{{${book.alias(c.entity)}}} ${c.entity.name}').join(', ');
    if (names.isNotEmpty) buf.writeln('${scan.kind.plural.toLowerCase()}${scan.role == 'channel' ? ' (channels)' : ''}: $names');
  }
  buf.writeln();
  final audience = kit.audience;
  if (audience != null && !audience.isEmpty) {
    buf.writeln('AUDIENCE');
    if (audience.age.isNotEmpty) {
      buf.writeln('age skew (positive = over-indexes): ${audience.age.entries.map((e) => '${e.key.label} ${e.value >= 0 ? '+' : ''}${fmt(e.value)}').join(', ')}');
    }
    if (audience.male != null) buf.writeln('gender skew: female ${fmt(audience.female ?? 0)}, male ${fmt(audience.male!)}');
    if (audience.descriptors.isNotEmpty) buf.writeln('taste descriptors: ${audience.descriptors.take(10).map((t) => t.name.toLowerCase()).join(', ')}');
    buf.writeln();
  }
  if (kit.markets.isNotEmpty) {
    buf.writeln('MARKETS (${b.marketInfo.name}; heatmap affinity vs popularity)');
    buf.writeln(kit.markets.take(6).map((m) => '${m.name} (${m.label.replaceAll('_', ' ')})').join(', '));
    buf.writeln();
  }
  if (kit.compCheck.isNotEmpty) {
    buf.writeln('COMP CHECK (comps the creator planned to use)');
    for (final v in kit.compCheck) {
      final r = v.resolved;
      buf.writeln('- "${v.input}" -> ${r == null ? 'not found' : '{{${book.alias(r)}}}'} · verdict ${v.verdict}'
          '${v.swap == null ? '' : ' · suggested swap {{${book.alias(v.swap!.entity)}}}'} · ${v.reasons.join(' ')}');
    }
    buf.writeln();
  }
  buf.writeln('COPY TO WRITE (ids and what each is for)');
  for (final spec in f.copySpecs) {
    buf.writeln('- ${spec.id}: ${spec.title}. ${spec.hint}');
  }
  buf.writeln();
  buf.writeln('Notes: comp_line is the "{{A}} meets {{B}}" line plus at most two sentences on why. '
      'pitch should read like the real document (a query letter paragraph keeps [word count] as a placeholder). '
      'fans_of is one line. ad_hooks is three bullet lines starting with "• ", each aimed at fans of one alias.');
  return buf.toString();
}

/// Lets the model write the kit's copy, with two optional Qloo tools for
/// checking claims. Output is validated; anything ungrounded is removed.
class Analyst {
  Analyst(this.llm, this.qloo);

  final LlmClient llm;
  final QlooService qloo;

  Future<CompKit> write(CompKit kit, Emitter emit, {String? instructions}) async {
    final book = AliasBook();
    final digest = buildDigest(kit, book);
    final messages = <Json>[
      {
        'role': 'user',
        'content': '$digest${instructions == null || instructions.trim().isEmpty ? '' : '\nCREATOR\'S REQUEST FOR THIS VERSION: ${instructions.trim()}\n'}\nWrite the kit now.',
      },
    ];
    Json? submission;
    var toolRounds = 0;
    for (var turn = 0; turn < 6 && submission == null; turn++) {
      emit.llm(turn == 0 ? 'Asked the model to write the pitch kit' : 'Model continued writing', data: {'call': true, 'model': llm.model});
      final response = await llm.create(system: analystSystem, messages: messages, tools: _tools, maxTokens: 12000);
      messages.add({'role': 'assistant', 'content': response.content});
      final uses = response.toolUses;
      if (uses.isEmpty) {
        final parsed = extractJsonObject(response.text);
        if (parsed != null && parsed['blocks'] != null) {
          submission = parsed;
          break;
        }
        messages.add({'role': 'user', 'content': 'Please call submit_copy now with the finished copy.'});
        continue;
      }
      final results = <Json>[];
      for (final use in uses) {
        if (use.name == 'submit_copy') {
          submission = use.input;
          results.add({'type': 'tool_result', 'tool_use_id': use.id, 'content': 'Received.'});
          continue;
        }
        if (toolRounds >= 3) {
          results.add({'type': 'tool_result', 'tool_use_id': use.id, 'content': 'Tool budget used up. Call submit_copy now.', 'is_error': true});
          continue;
        }
        toolRounds++;
        results.add(await _runTool(use, kit, book, emit));
      }
      if (submission != null) break;
      messages.add({'role': 'user', 'content': results});
    }
    if (submission == null) {
      emit.warn('The model did not submit copy; kept the evidence-only templates');
      return kit;
    }
    return _apply(kit, submission, book, emit);
  }

  Future<Json> _runTool(ToolUse use, CompKit kit, AliasBook book, Emitter emit) async {
    try {
      if (use.name == 'check_fit') {
        final entities = stringsOf(use.input['aliases']).map(book.entityOf).whereType<Entity>().toList();
        if (entities.isEmpty) return _toolError(use, 'No known aliases given.');
        final kind = entities.first.kind;
        final same = entities.where((e) => e.kind == kind).toList();
        emit.decision('Model is checking a claim', 'Fit of ${same.map((e) => e.name).join(', ')}');
        final fits = await qloo.fitOf(
          kind: kind,
          signalIds: kit.anchors.map((a) => a.id).toList(),
          candidateIds: same.map((e) => e.id).toList(),
          label: 'Checked fit for the model',
        );
        final lines = same.map((e) => '${book.alias(e)}: ${fits[e.id]?.toStringAsFixed(2) ?? 'no affinity returned'}').join('\n');
        return {'type': 'tool_result', 'tool_use_id': use.id, 'content': lines};
      }
      if (use.name == 'compare_audiences') {
        final a = stringsOf(use.input['a']).map(book.idOf).whereType<String>().toList();
        final b = stringsOf(use.input['b']).map(book.idOf).whereType<String>().toList();
        if (a.isEmpty || b.isEmpty) return _toolError(use, 'Both groups need known aliases.');
        emit.decision('Model is comparing two audiences');
        final tags = await qloo.compare(a, b, label: 'Compared audiences for the model');
        final text = tags.isEmpty ? 'Qloo returned no shared tags.' : 'Shared taste tags: ${tags.take(10).map((t) => t.name.toLowerCase()).join(', ')}';
        return {'type': 'tool_result', 'tool_use_id': use.id, 'content': text};
      }
      return _toolError(use, 'Unknown tool.');
    } on QlooException catch (e) {
      return _toolError(use, 'Qloo error: ${e.message}');
    }
  }

  Json _toolError(ToolUse use, String message) =>
      {'type': 'tool_result', 'tool_use_id': use.id, 'content': message, 'is_error': true};

  CompKit _apply(CompKit kit, Json submission, AliasBook book, Emitter emit) {
    final unknown = <String>[];
    String clean(String? text) {
      if (text == null) return '';
      final (out, missing) = resolveRefs(text, book);
      unknown.addAll(missing);
      return out;
    }

    final specs = {for (final s in kit.brief.format.copySpecs) s.id: s};
    final byId = {for (final c in kit.copy) c.id: c};
    for (final item in asList(submission['blocks'])) {
      final json = asJson(item);
      final id = asString(json['id']);
      final spec = id == null ? null : specs[id];
      if (spec == null) continue;
      final body = clean(asString(json['body']));
      if (body.length < 8) continue;
      byId[id!] = CopyBlock(id: id, title: spec.title, hint: spec.hint, body: body, author: 'llm');
    }
    final ordered = [for (final s in kit.brief.format.copySpecs) if (byId[s.id] != null) byId[s.id]!];

    // Accept the model's pairing only if both picks are primary comps.
    var pairing = kit.pairing;
    final pair = asJson(submission['pair']);
    final pa = book.idOf(asString(pair['a']) ?? ''), pb = book.idOf(asString(pair['b']) ?? '');
    if (pa != null && pb != null && pa != pb) {
      final items = {for (final c in kit.primary.items) c.entity.id: c};
      final ca = items[pa], cb = items[pb];
      if (ca != null && cb != null && pairing != null && !(pairing.a.entity.id == pa && pairing.b.entity.id == pb)) {
        pairing = CompPairing(a: ca, b: cb, score: pairing.score, alternatives: pairing.alternatives, why: null);
        emit.decision('Model chose a different comp line', pairing.line);
      }
    }

    final headline = clean(asString(submission['headline']));
    final summary = clean(asString(submission['summary']));
    if (unknown.isNotEmpty) {
      emit.warn('Removed ${unknown.length} reference${unknown.length == 1 ? '' : 's'} the model could not ground', unknown.toSet().join(', '));
    }
    emit.llm('Model wrote ${ordered.where((c) => c.author == 'llm').length} copy blocks', data: {'blocks': jsonEncode(ordered.map((c) => c.id).toList())});
    return kit.copyWith(
      copy: ordered,
      headline: headline.isEmpty ? kit.headline : headline,
      summary: summary.isEmpty ? kit.summary : summary,
      pairing: pairing,
    );
  }
}
