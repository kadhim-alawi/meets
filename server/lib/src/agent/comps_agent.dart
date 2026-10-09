import 'dart:async';

import 'package:meets_core/meets_core.dart';

import '../llm/anthropic.dart';
import '../qloo/qloo_client.dart';
import 'analyst.dart';
import 'composer.dart';
import 'emitter.dart';
import 'planner.dart';
import 'qloo_service.dart';

/// A failure the creator can act on (shown verbatim in the UI).
class AgentFailure implements Exception {
  AgentFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

String normalizeTitle(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim()
    .replaceFirst(RegExp(r'^the '), '');

/// Picks the search result that is really the thing the creator named.
Entity? pickMatch(String name, List<Entity> results, {EntityKind? kind, EntityKind? prefer}) {
  if (results.isEmpty) return null;
  final target = normalizeTitle(name);
  int kindScore(Entity e) => e.kind == kind ? 2 : (e.kind == prefer ? 1 : 0);
  int byKindThenPop(Entity a, Entity b) {
    final k = kindScore(b) - kindScore(a);
    if (k != 0) return k;
    return (b.popularity ?? 0).compareTo(a.popularity ?? 0);
  }

  final exact = results.where((e) => normalizeTitle(e.name) == target).toList()..sort(byKindThenPop);
  if (exact.isNotEmpty) return exact.first;
  final partial = results.where((e) {
    final n = normalizeTitle(e.name);
    return n.startsWith(target) || target.startsWith(n) || n.contains(target);
  }).toList()
    ..sort(byKindThenPop);
  if (partial.isNotEmpty) return partial.first;
  // Fall back to Qloo's own best match only when it shares real words.
  final words = target.split(' ').where((w) => w.length > 2).toSet();
  final first = results.first;
  final overlap = normalizeTitle(first.name).split(' ').where(words.contains).length;
  return words.isNotEmpty && overlap / words.length >= 0.5 ? first : null;
}

/// Merges two affinity-ranked lists of the same request family.
List<Entity> mergeByAffinity(List<Entity> a, List<Entity> b) {
  final byId = <String, Entity>{};
  for (final e in [...a, ...b]) {
    byId.putIfAbsent(e.id, () => e);
  }
  final list = byId.values.toList();
  final order = {for (var i = 0; i < list.length; i++) list[i].id: i};
  list.sort((x, y) {
    final ax = x.affinity, ay = y.affinity;
    if (ax != null && ay != null && ax != ay) return ay.compareTo(ax);
    return order[x.id]!.compareTo(order[y.id]!);
  });
  return list;
}

/// The Meets agent: turns a [Brief] into a [CompKit], narrating each step.
class CompsAgent {
  CompsAgent({required this.client, this.llm, DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final QlooClient client;
  final LlmClient? llm;
  final DateTime Function() _clock;
  final Composer composer = const Composer();

  Future<CompKit> build(
    Brief brief,
    Emitter emit, {
    required String kitId,
    int version = 1,
    String? copyInstructions,
  }) async {
    final started = DateTime.now();
    final qloo = QlooService(client, emit);
    final year = _clock().year;
    final format = brief.format;
    final notes = <String>[];

    // 1. Read the brief -------------------------------------------------------
    emit.step('Reading your brief',
        '${format.label}${brief.title.isEmpty ? '' : ' · ${brief.title}'} · ${brief.anchors.length} touchstone${brief.anchors.length == 1 ? '' : 's'}');
    var anchorInputs = [...brief.anchors];
    var themes = [...brief.themes];
    final model = llm;
    if (model != null && brief.logline.trim().isNotEmpty && (Planner.wanted(brief) > 0 || themes.isEmpty)) {
      try {
        final plan = await Planner(model).plan(brief, emit);
        if (plan.reading != null) emit.decision('Read the project as: ${plan.reading}');
        if (plan.touchstones.isNotEmpty) {
          emit.decision('Proposed ${plan.touchstones.length} more touchstone${plan.touchstones.length == 1 ? '' : 's'} to verify in Qloo',
              plan.touchstones.map((t) => '${t.name}${t.kind == null ? '' : ' (${t.kind!.label})'}').join(' · '));
          anchorInputs = [...anchorInputs, ...plan.touchstones];
        }
        if (themes.isEmpty && plan.themes.isNotEmpty) {
          themes = plan.themes;
          emit.decision('Picked themes to lean into', themes.join(' · '));
        }
      } on LlmException catch (e) {
        emit.warn('The model could not read the brief; continuing with your inputs', e.message);
      }
    }
    if (anchorInputs.isEmpty) {
      throw AgentFailure('Add at least one touchstone — a book, film, show, artist or game your audience already loves.');
    }

    // 2. Resolve touchstones --------------------------------------------------
    emit.step('Finding your touchstones in Qloo');
    final anchors = await _resolveAnchors(qloo, anchorInputs, format, emit);
    if (anchors.isEmpty) {
      throw AgentFailure('Qloo did not recognise any of your touchstones. Try exact titles, or pick them from the suggestions.');
    }
    final anchorIds = anchors.map((a) => a.id).toList();
    final anchorNames = {for (final a in anchors) a.id: a.name};

    // 3. Themes -> tags -------------------------------------------------------
    final themeTags = themes.isEmpty ? <TagRef>[] : await _resolveThemes(qloo, themes.take(4).toList(), format, emit);

    // 4. Scans, in parallel where independent -------------------------------
    emit.step('Scanning the taste graph',
        'Comps from ${format.primary.plural.toLowerCase()}, plus ${format.cross.map((k) => k.plural.toLowerCase()).join(', ')}');
    // Start the primary scan first so it gets the earliest request slots.
    final primaryFuture = _primaryScan(qloo, brief, anchorIds, anchorNames, themeTags, year, emit);
    final crossFuture = Future.wait([
      for (final kind in format.cross) _contextScan(qloo, kind, 'cross', anchorIds, brief, year, anchorNames, emit),
    ]);
    final channelFuture = Future.wait([
      for (final kind in format.channels) _contextScan(qloo, kind, 'channel', anchorIds, brief, year, anchorNames, emit),
    ]);
    final audienceFuture = _audience(qloo, anchorIds, anchors, format, emit, notes);
    final marketsFuture = _markets(qloo, anchorIds, brief, emit, notes);

    final primary = await primaryFuture;
    if (primary.items.isEmpty) {
      throw AgentFailure('Qloo returned no ${format.primary.plural.toLowerCase()} for these touchstones. Try adding a better-known one.');
    }

    // 5. Pairing and comp check ----------------------------------------------
    final pairing = await _pairing(qloo, primary, emit, notes);
    final compCheck = brief.myComps.isEmpty
        ? const <CompVerdict>[]
        : await _compCheck(qloo, brief, anchorIds, primary, year, emit, notes);

    final cross = (await crossFuture).whereType<DomainScan>().toList();
    final channels = (await channelFuture).whereType<DomainScan>().toList();
    final audience = await audienceFuture;
    final markets = await marketsFuture;

    var kit = CompKit(
      id: kitId,
      createdAt: DateTime.now().toUtc(),
      brief: brief.copyWith(anchors: anchorInputs, themes: themes),
      mode: client.mode,
      version: version,
      anchors: anchors,
      themes: themeTags,
      primary: primary,
      cross: cross,
      channels: channels,
      pairing: pairing,
      audience: audience,
      markets: markets,
      compCheck: compCheck,
    );

    // 6. Write the kit --------------------------------------------------------
    emit.step('Writing your pitch kit');
    kit = kit.copyWith(
      copy: composer.copy(kit),
      headline: composer.headline(kit),
      summary: composer.summary(kit),
    );
    if (model != null) {
      try {
        kit = await Analyst(model, qloo).write(kit, emit, instructions: copyInstructions);
      } on LlmException catch (e) {
        emit.warn('The model could not write copy; using the evidence-only templates', e.message);
        notes.add('Copy was written from templates because the language model was unavailable.');
      }
    } else {
      notes.add('Copy was written from templates (no language model configured).');
    }

    final allNotes = [...notes, ...composer.standardNotes(kit)];
    final stats = KitStats(
      qlooCalls: emit is ListEmitter ? emit.qlooCalls : 0,
      cachedCalls: emit is ListEmitter ? emit.cachedCalls : 0,
      llmCalls: emit is ListEmitter ? emit.llmCalls : 0,
      durationMs: DateTime.now().difference(started).inMilliseconds,
      model: model?.model,
    );
    kit = CompKit(
      id: kit.id,
      createdAt: kit.createdAt,
      brief: kit.brief,
      mode: kit.mode,
      version: kit.version,
      anchors: kit.anchors,
      themes: kit.themes,
      primary: kit.primary,
      cross: kit.cross,
      channels: kit.channels,
      pairing: kit.pairing,
      audience: kit.audience,
      markets: kit.markets,
      compCheck: kit.compCheck,
      copy: kit.copy,
      targeting: composer.targeting(kit),
      baseline: kit.baseline,
      headline: kit.headline,
      summary: kit.summary,
      notes: allNotes,
      stats: stats,
    );
    emit.emit('done', 'Comp kit ready',
        detail: '${stats.qlooCalls} Qloo calls${stats.cachedCalls > 0 ? ' (${stats.cachedCalls} from cache)' : ''} · ${(stats.durationMs / 1000).toStringAsFixed(1)}s');
    return kit;
  }

  /// Rewrites only the copy of an existing kit (no new scans).
  Future<CompKit> rewriteCopy(CompKit kit, Emitter emit, String? instructions) async {
    final model = llm;
    if (model == null) return kit;
    emit.step('Rewriting the copy', instructions);
    return Analyst(model, QlooService(client, emit)).write(kit, emit, instructions: instructions);
  }

  // -- steps -----------------------------------------------------------------

  Future<List<Entity>> _resolveAnchors(QlooService qloo, List<AnchorInput> inputs, WorkFormat format, Emitter emit) async {
    final byId = <String, Entity>{};
    final withIds = inputs.where((a) => a.id != null).toList();
    if (withIds.isNotEmpty) {
      try {
        final found = await qloo.entities(withIds.map((a) => a.id!).toList(),
            label: 'Loaded ${withIds.length} picked touchstone${withIds.length == 1 ? '' : 's'}');
        for (final e in found) {
          byId[e.id] = e;
        }
      } on QlooException {
        // Fall back to name search below.
      }
    }
    final searchKinds = {format.primary, ...format.cross, EntityKind.person}.toList();
    final results = await Future.wait(inputs.map((input) async {
      if (input.id != null && byId.containsKey(input.id)) return byId[input.id];
      final kinds = input.kind == null ? searchKinds : [input.kind!];
      try {
        final found = await qloo.search(input.name, kinds: kinds, take: 6, label: 'Looked up "${input.name}"');
        final match = pickMatch(input.name, found, kind: input.kind, prefer: format.primary);
        if (match == null) {
          emit.warn('Skipped "${input.name}"', 'Qloo had no close match${input.suggested ? ' for this suggestion' : ''}.');
        } else if (input.suggested) {
          emit.decision('Verified suggestion: ${match.name}', '${match.kind.label}${match.year == null ? '' : ', ${match.year}'}');
        }
        return match;
      } on QlooException catch (e) {
        emit.warn('Could not look up "${input.name}"', e.message);
        return null;
      }
    }));
    final out = <Entity>[];
    for (final e in results.whereType<Entity>()) {
      if (!out.any((x) => x.id == e.id)) out.add(e);
    }
    return out;
  }

  Future<List<TagRef>> _resolveThemes(QlooService qloo, List<String> themes, WorkFormat format, Emitter emit) async {
    final found = await Future.wait(themes.map((theme) async {
      try {
        final tags = await qloo.tags(theme, parent: format.primary, take: 6, label: 'Matched the theme "$theme" to a Qloo tag');
        if (tags.isEmpty) return null;
        final target = normalizeTitle(theme);
        return tags.firstWhere((t) => normalizeTitle(t.name) == target,
            orElse: () => tags.firstWhere((t) => const {'genre', 'subgenre', 'keyword', 'theme', 'style'}.contains(t.family),
                orElse: () => tags.first));
      } on QlooException {
        return null;
      }
    }));
    final out = <TagRef>[];
    for (final t in found.whereType<TagRef>()) {
      if (!out.any((x) => x.id == t.id)) out.add(t);
    }
    if (out.isNotEmpty) emit.decision('Themes mapped to Qloo tags', out.map((t) => t.name).join(' · '));
    return out;
  }

  String _yearPhrase(WorkFormat format, int minYear) => switch (format.primary) {
        EntityKind.book => 'Published $minYear or later',
        EntityKind.tvShow => 'On air $minYear or later',
        _ => 'Released $minYear or later',
      };

  Future<DomainScan> _primaryScan(
    QlooService qloo,
    Brief brief,
    List<String> anchorIds,
    Map<String, String> anchorNames,
    List<TagRef> themeTags,
    int year,
    Emitter emit,
  ) async {
    final format = brief.format;
    final kind = format.primary;
    final filters = <String>[];
    final notes = <String>[];
    final params = <String, Object?>{
      'filter.type': kind.urn,
      'signal.interests.entities': anchorIds,
      'signal.interests.tags': themeTags.map((t) => t.id).toList(),
      'signal.demographics.age': brief.ages.map((a) => a.key).toList(),
      'filter.exclude.entities': {...anchorIds, ...brief.excludeIds}.toList(),
      'feature.explainability': true,
      'take': 40,
    };
    int? minYear;
    if (format.recencyParam != null && brief.recencyYears > 0) {
      minYear = year - brief.recencyYears;
      params[format.recencyParam!] = minYear;
    }
    if (themeTags.isNotEmpty) filters.add('Leaning into ${themeTags.map((t) => t.name.toLowerCase()).join(', ')}');
    if (brief.ages.isNotEmpty) filters.add('Weighted toward ages ${brief.ages.map((a) => a.label).join(', ')}');

    final label = 'Scanned ${kind.plural.toLowerCase()} loved by your audience';
    var list = await qloo.insights(params, label: label);

    if (list.length < 8 && themeTags.isNotEmpty) {
      emit.decision('Only ${list.length} matches with themes in the signal', 'Retrying on your touchstones alone.');
      params.remove('signal.interests.tags');
      filters.removeWhere((f) => f.startsWith('Leaning'));
      notes.add('Themes were dropped from the signal because they narrowed results too far.');
      list = await qloo.insights(params, label: '$label (touchstones only)');
    }
    if (list.length < 8 && minYear != null) {
      minYear -= 5;
      params[format.recencyParam!] = minYear;
      emit.decision('Only ${list.length} recent matches', 'Widened the window by five years, to $minYear.');
      notes.add('The recency window was widened to $minYear because recent matches were thin.');
      list = await qloo.insights(params, label: '$label (wider window)');
    }
    if (minYear != null) filters.insert(0, _yearPhrase(format, minYear));

    // Qloo ranks by affinity, so the head of the list is often blockbusters.
    // When too few results sit in the creator's size range, dig deeper.
    if (brief.size != SizePref.mainstream && list.isNotEmpty) {
      final bands = targetBands(brief.size);
      final inBand = list.where((e) => bands.contains(SizeBand.of(e.popularity))).length;
      if (inBand < 6) {
        final cap = brief.size == SizePref.indie ? 0.99 : 0.999;
        final bigger = list.where((e) => SizeBand.of(e.popularity).bigness > bands.map((b) => b.bigness).reduce((x, y) => x > y ? x : y)).length;
        emit.decision(
          'Only $inBand of ${list.length} results are ${brief.size.label.toLowerCase()}-sized',
          '$bigger are bigger than useful comps. Digging below the top ${((1 - cap) * 100).toStringAsFixed(1)}% for right-sized ${kind.plural.toLowerCase()}.',
        );
        try {
          final deeper = await qloo.insights({...params, 'filter.popularity.max': cap},
              label: 'Dug below the top ${((1 - cap) * 100).toStringAsFixed(1)}% for right-sized ${kind.plural.toLowerCase()}');
          list = mergeByAffinity(list, deeper);
          notes.add('Added a second pass below the top ${((1 - cap) * 100).toStringAsFixed(1)}% of popularity to find right-sized comps.');
        } on QlooException catch (e) {
          emit.warn('The deeper pass failed', e.message);
        }
      }
    }

    if (kind == EntityKind.person) {
      bool comic(Entity e) => e.tags.any((t) => t.name.toLowerCase().contains('comed') || t.name.toLowerCase().contains('stand'));
      final comedians = list.where(comic).toList();
      if (comedians.length >= 5) {
        list = [...comedians, ...list.where((e) => !comic(e))];
        emit.decision('Put comedians first', '${comedians.length} of ${list.length} people are tagged as comedy.');
      }
    }

    final scored = scoreCandidates(
      list,
      size: brief.size,
      recencyYears: brief.recencyYears,
      currentYear: year,
      anchorNames: anchorNames,
      applyRecency: brief.recencyYears > 0 && (kind.hasYear || kind == EntityKind.videoGame),
    );
    return DomainScan(kind: kind, role: 'primary', items: rankForDisplay(scored).take(24).toList(), filters: filters, notes: notes);
  }

  Future<DomainScan?> _contextScan(
    QlooService qloo,
    EntityKind kind,
    String role,
    List<String> anchorIds,
    Brief brief,
    int year,
    Map<String, String> anchorNames,
    Emitter emit,
  ) async {
    try {
      final list = await qloo.insights({
        'filter.type': kind.urn,
        'signal.interests.entities': anchorIds,
        'signal.demographics.age': brief.ages.map((a) => a.key).toList(),
        'filter.exclude.entities': anchorIds,
        'feature.explainability': true,
        'take': 12,
      }, label: role == 'channel' ? 'Found ${kind.plural.toLowerCase()} this audience follows' : 'Checked which ${kind.plural.toLowerCase()} the same people love');
      final scored = scoreCandidates(list,
          size: brief.size, recencyYears: 0, currentYear: year, anchorNames: anchorNames, applyRecency: false, applySize: false);
      return DomainScan(kind: kind, role: role, items: scored.take(10).toList());
    } on QlooException catch (e) {
      emit.warn('Skipped ${kind.plural.toLowerCase()}', e.message);
      return null;
    }
  }

  Future<AudienceProfile?> _audience(
      QlooService qloo, List<String> anchorIds, List<Entity> anchors, WorkFormat format, Emitter emit, List<String> notes) async {
    AudienceProfile? demo;
    var descriptors = <TagRef>[];
    await Future.wait([
      () async {
        try {
          demo = await qloo.demographics(anchorIds, label: 'Measured the audience\'s age and gender skew');
        } on QlooException catch (e) {
          emit.warn('No demographics for this audience', e.message);
        }
      }(),
      () async {
        try {
          final anchorNameSet = anchors.map((a) => normalizeTitle(a.name)).toSet();
          descriptors = (await qloo.tasteTags(anchorIds, parent: format.primary, take: 30, label: 'Read the audience\'s taste descriptors'))
              .where((t) => !anchorNameSet.contains(normalizeTitle(t.name)))
              .take(14)
              .toList();
        } on QlooException catch (e) {
          emit.warn('No taste descriptors for this audience', e.message);
        }
      }(),
    ]);
    final d = demo;
    if (d == null && descriptors.isEmpty) {
      notes.add('Qloo returned no audience profile for these touchstones.');
      return null;
    }
    return AudienceProfile(age: d?.age ?? const {}, male: d?.male, female: d?.female, descriptors: descriptors);
  }

  Future<List<MarketCity>> _markets(QlooService qloo, List<String> anchorIds, Brief brief, Emitter emit, List<String> notes) async {
    final market = brief.marketInfo;
    if (market.code == Market.global.code) return const [];
    try {
      final cells = await qloo.heatmap(anchorIds, market.query, label: 'Mapped where this audience clusters in ${market.name}');
      final markets = aggregateMarkets(cells, citiesFor(market.code));
      if (markets.isEmpty) notes.add('Qloo\'s heatmap for ${market.name} did not resolve to named cities.');
      return markets;
    } on QlooException catch (e) {
      emit.warn('Skipped the market map', e.message);
      notes.add('The market map for ${market.name} was unavailable.');
      return const [];
    }
  }

  Future<CompPairing?> _pairing(QlooService qloo, DomainScan primary, Emitter emit, List<String> notes) async {
    final ranked = rankForDisplay(primary.items);
    final sweet = ranked.where((c) => c.isSweetSpot).toList();
    final pool = (sweet.length >= 3 ? sweet : ranked).take(5).toList();
    if (pool.length < 2) return null;
    emit.step('Testing pairings for your comp line', '${pool.length} front-runners, ${pool.length * (pool.length - 1) ~/ 2} pairs');
    final sims = <String, double>{};
    await Future.wait(pool.take(4).map((a) async {
      final others = pool.where((c) => c.entity.id != a.entity.id).map((c) => c.entity.id).toList();
      try {
        final fits = await qloo.fitOf(
            kind: primary.kind, signalIds: [a.entity.id], candidateIds: others, label: 'Measured how alike "${a.entity.name}" is to the others');
        fits.forEach((b, aff) => sims['${a.entity.id}|$b'] = aff);
      } on QlooException {
        // Tag overlap stands in for missing similarity.
      }
    }));
    var pairing = choosePairing(pool, (x, y) => sims['$x|$y'], pool: pool.length);
    if (pairing == null) return null;

    final a = pairing.a.entity, b = pairing.b.entity;
    var shared = <String>[];
    try {
      final tags = await qloo.compare([a.id], [b.id], label: 'Compared the audiences of "${a.name}" and "${b.name}"');
      shared = tags.take(4).map((t) => t.name.toLowerCase()).toList();
    } on QlooException {
      // Fall back to local tag overlap.
    }
    final aTags = a.tags.map((t) => t.name.toLowerCase()).toList();
    final bTags = b.tags.map((t) => t.name.toLowerCase()).toList();
    if (shared.isEmpty) shared = aTags.where(bTags.contains).take(3).toList();
    final aOnly = aTags.where((t) => !bTags.contains(t) && !shared.contains(t)).take(2).toList();
    final bOnly = bTags.where((t) => !aTags.contains(t) && !shared.contains(t)).take(2).toList();
    final why = [
      if (aOnly.isNotEmpty) '${a.name} brings the ${Composer.joinNames(aOnly)}',
      if (bOnly.isNotEmpty) '${b.name} brings the ${Composer.joinNames(bOnly)}',
      if (shared.isNotEmpty) 'fans of both share a taste for ${Composer.joinNames(shared)}',
    ];
    pairing = CompPairing(
      a: pairing.a,
      b: pairing.b,
      similarity: pairing.similarity,
      score: pairing.score,
      alternatives: pairing.alternatives,
      why: why.isEmpty ? null : '${why.join('; ')}.'.replaceFirst(RegExp(r'^.'), why.first[0].toUpperCase()),
    );
    emit.decision('Comp line: ${pairing.line}',
        pairing.similarity == null ? 'Strong, right-sized and different from each other.' : 'Qloo similarity ${(pairing.similarity! * 100).round()}% — close enough to share fans, different enough to triangulate.');
    return pairing;
  }

  Future<List<CompVerdict>> _compCheck(QlooService qloo, Brief brief, List<String> anchorIds, DomainScan primary, int year,
      Emitter emit, List<String> notes) async {
    emit.step('Checking the comps you planned to use', brief.myComps.map((c) => c.name).join(' · '));
    final format = brief.format;
    final resolved = await Future.wait(brief.myComps.map((input) async {
      try {
        final kinds = input.kind == null ? [format.primary] : [input.kind!];
        final found = input.id != null
            ? await qloo.entities([input.id!], label: 'Loaded your comp "${input.name}"')
            : await qloo.search(input.name, kinds: kinds, take: 6, label: 'Looked up your comp "${input.name}"');
        return (input, pickMatch(input.name, found, kind: input.kind ?? format.primary, prefer: format.primary) ?? (input.id != null && found.isNotEmpty ? found.first : null));
      } on QlooException {
        return (input, null);
      }
    }));

    final byKind = <EntityKind, List<Entity>>{};
    for (final (_, e) in resolved) {
      if (e != null) (byKind[e.kind] ??= []).add(e);
    }
    final fits = <String, double>{};
    for (final entry in byKind.entries) {
      try {
        fits.addAll(await qloo.fitOf(
            kind: entry.key,
            signalIds: anchorIds,
            candidateIds: entry.value.map((e) => e.id).toList(),
            label: 'Scored your ${entry.key.plural.toLowerCase()} against the audience'));
      } on QlooException catch (e) {
        emit.warn('Could not score your comps', e.message);
      }
    }

    final reference = primary.items.map((c) => c.entity.affinity).whereType<double>().toList()..sort();
    double? percentile(double? aff) {
      if (aff == null || reference.isEmpty) return aff;
      final below = reference.where((r) => r <= aff).length;
      return below / reference.length;
    }

    final used = <String>{};
    final sweet = rankForDisplay(primary.items).where((c) => c.isSweetSpot).toList();
    final out = <CompVerdict>[];
    for (final (input, e) in resolved) {
      if (e == null) {
        out.add(CompVerdict(input: input.name, verdict: 'not_found', reasons: const ['Qloo did not find a close match for this title.']));
        continue;
      }
      final aff = fits[e.id];
      final fit = percentile(aff);
      final size = SizeBand.of(e.popularity);
      final recency = e.kind.hasYear ? recencyOf(e.year, brief.recencyYears, year) : null;
      final reasons = <String>[];
      final sw = sizeWeight(size, brief.size);
      final targets = targetBands(brief.size);
      final tooBig = size != SizeBand.unknown && size.bigness > targets.map((b) => b.bigness).reduce((x, y) => x > y ? x : y) && sw <= 0.6;
      if (tooBig) {
        reasons.add('${topPercentLabel(e.popularity)} in popularity: buyers read this as a comparison to a phenomenon, not a market signal.');
      }
      if (brief.recencyYears > 0 && (recency == RecencyBand.dated || recency == RecencyBand.classic)) {
        reasons.add('From ${e.year}, outside your ${brief.recencyYears}-year window. Buyers want proof the audience is buying now.');
      }
      if (aff == null) {
        reasons.add('Qloo returned no affinity between this title and your touchstones.');
      } else if (fit != null && fit < 0.35) {
        reasons.add(fit < 0.05
            ? 'Weaker audience overlap than any comp Meets found.'
            : 'Weaker audience overlap than ${((1 - fit) * 100).round()}% of the comps Meets found.');
      }
      final ok = reasons.isEmpty;
      if (ok) {
        reasons.add('Right-sized (${topPercentLabel(e.popularity)})${e.year == null ? '' : ', ${e.year}'}, with strong audience overlap.');
      }
      Candidate? swap;
      if (!ok) {
        swap = sweet.firstWhere(
          (c) => !used.contains(c.entity.id) && c.entity.tags.any((t) => e.tags.any((x) => x.id == t.id)),
          orElse: () => sweet.firstWhere((c) => !used.contains(c.entity.id), orElse: () => sweet.isEmpty ? primary.items.first : sweet.first),
        );
        used.add(swap.entity.id);
      }
      out.add(CompVerdict(
        input: input.name,
        resolved: e.copyWith(affinity: aff),
        fit: fit,
        size: size,
        recency: recency,
        verdict: ok ? 'keep' : 'swap',
        reasons: reasons,
        swap: swap,
      ));
    }
    final swaps = out.where((v) => v.verdict == 'swap').length;
    if (swaps > 0) emit.decision('Flagged $swaps of your comps', 'Suggested right-sized swaps for each.');
    return out;
  }
}
