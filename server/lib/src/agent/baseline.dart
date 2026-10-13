import 'package:meets_core/meets_core.dart';

import '../llm/anthropic.dart';
import '../qloo/qloo_client.dart';
import 'comps_agent.dart';
import 'emitter.dart';
import 'qloo_service.dart';

const _baselineSystem = '''
You are a well-read assistant with no tools and no data access. A creator asks you for comparable titles ("comps") for their project. Answer from general knowledge only, the way a chat assistant would. Call submit_titles once.''';

final _submitTitles = toolDef(
  'submit_titles',
  'Submit your comps.',
  {
    'titles': {
      'type': 'array',
      'items': {
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
          'year': {'type': 'integer'},
        },
        'required': ['name'],
      },
    },
  },
  required: ['titles'],
);

/// Asks the model for comps *without* Qloo, then checks each suggestion
/// against the same Qloo evidence. Shows what the taste graph adds.
class GutCheck {
  GutCheck(this.llm, this.client);

  final LlmClient llm;
  final QlooClient client;

  Future<BaselineResult> run(CompKit kit, Emitter emit, {int currentYear = 0}) async {
    final year = currentYear == 0 ? DateTime.now().year : currentYear;
    final qloo = QlooService(client, emit);
    final b = kit.brief;
    final f = b.format;
    emit.step('Asking a plain LLM for comps', 'Same brief, no Qloo, no tools.');
    // Only what the creator typed: Meets' own Qloo-verified suggestions would leak into the baseline.
    final own = b.anchors.where((a) => !a.suggested).map((a) => a.name).toList();
    final prompt = '''
I'm pitching a ${f.label.toLowerCase()}${b.title.isEmpty ? '' : ' called "${b.title}"'}.
${b.logline.isEmpty ? '' : 'It is about: ${b.logline}\n'}${own.isEmpty ? '' : "It's like: ${own.join(', ')}.\n"}Give me 6 comparable ${f.primary.plural.toLowerCase()}${own.isEmpty ? '' : ' other than those'} that I should use as comps${b.recencyYears > 0 ? ' (ideally from the last ${b.recencyYears} years)' : ''}.''';
    emit.llm('Asked the model without tools', data: {'call': true, 'model': llm.model});
    final response = await llm.create(
      system: _baselineSystem,
      messages: [
        {'role': 'user', 'content': prompt},
      ],
      tools: [_submitTitles],
      maxTokens: 3000,
      effortOverride: 'low',
    );
    final input = response.toolUses.where((t) => t.name == 'submit_titles').map((t) => t.input).firstOrNull ??
        extractJsonObject(response.text) ??
        const <String, dynamic>{};
    final names = asList(input['titles'])
        .map((t) => asString(asJson(t)['name']) ?? asString(t))
        .whereType<String>()
        .map((n) => n.trim())
        .where((n) => n.isNotEmpty)
        .take(8)
        .toList();
    emit.decision('The plain LLM suggested ${names.length} comps', names.join(' · '));

    emit.step('Checking each suggestion against Qloo');
    final resolved = await Future.wait(names.map((name) async {
      try {
        final found = await qloo.search(name, kinds: [f.primary], take: 5, label: 'Looked up "$name"');
        return (name, pickMatch(name, found, kind: f.primary));
      } on QlooException {
        return (name, null);
      }
    }));
    final anchorIds = kit.anchors.map((a) => a.id).toSet();
    final ids = resolved.map((r) => r.$2?.id).whereType<String>().where((id) => !anchorIds.contains(id)).toList();
    final meetsIds = kit.primary.items.map((c) => c.entity.id).toList();
    var fits = <String, double>{};
    if (ids.isNotEmpty) {
      try {
        // Meets' own comps ride in the same request: affinities from different
        // signals sit on different scales and can't be compared.
        fits = await qloo.fitOf(
            kind: f.primary,
            signalIds: anchorIds.toList(),
            candidateIds: {...ids, ...meetsIds}.toList(),
            label: 'Scored the LLM\'s picks and Meets\' comps against the same audience');
      } on QlooException catch (e) {
        emit.warn('Could not score the suggestions', e.message);
      }
    }
    final reference = meetsIds.map((id) => fits[id]).whereType<double>().toList()..sort();
    double? percentile(double? aff) =>
        aff == null || reference.isEmpty ? aff : reference.where((r) => r <= aff).length / reference.length;

    final items = <BaselineItem>[];
    for (final (name, e) in resolved) {
      if (e == null) {
        items.add(BaselineItem(name: name, verdict: 'not_found'));
        continue;
      }
      if (anchorIds.contains(e.id)) {
        items.add(BaselineItem(name: name, resolved: e, verdict: 'touchstone'));
        continue;
      }
      final aff = fits[e.id];
      final fit = percentile(aff);
      final size = SizeBand.of(e.popularity);
      final recency = f.primary.hasYear ? recencyOf(e.year, b.recencyYears, year) : null;
      final targets = targetBands(b.size);
      final tooBig = size != SizeBand.unknown &&
          size.bigness > targets.map((t) => t.bigness).reduce((x, y) => x > y ? x : y) &&
          sizeWeight(size, b.size) <= 0.6;
      final verdict = tooBig
          ? 'too_big'
          : (b.recencyYears > 0 && (recency == RecencyBand.dated || recency == RecencyBand.classic))
              ? 'dated'
              : (aff == null || (fit != null && fit < 0.35))
                  ? 'weak_fit'
                  : 'strong';
      items.add(BaselineItem(name: name, resolved: e.copyWith(affinity: aff), fit: fit, size: size, recency: recency, verdict: verdict));
    }

    int count(String v) => items.where((i) => i.verdict == v).length;
    final parts = <String>[
      '${count('strong')} of ${items.length} hold up as comps',
      if (count('too_big') > 0) '${count('too_big')} are too big to position against',
      if (count('dated') > 0) '${count('dated')} fall outside your recency window',
      if (count('weak_fit') > 0) '${count('weak_fit')} have a weak audience overlap',
      if (count('not_found') > 0) '${count('not_found')} could not be found in Qloo',
      if (count('touchstone') > 0) '${count('touchstone')} ${count('touchstone') == 1 ? 'is' : 'are'} already a touchstone in this kit',
    ];
    final summary = '${parts.join(', ')}.';
    emit.emit('done', 'Gut check complete', detail: summary);
    return BaselineResult(model: llm.model, items: items, summary: summary);
  }
}
