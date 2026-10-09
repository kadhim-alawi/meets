import 'package:flutter/material.dart';
import 'package:meets_core/meets_core.dart';

import '../api.dart';
import '../theme.dart';
import 'common.dart';
import 'touchstone_field.dart';

/// The brief form: what you're making, what it's like, and a few dials.
class Composer extends StatefulWidget {
  const Composer({super.key, required this.onSubmit, required this.health, this.busy = false, this.initial});

  final Future<void> Function(Brief brief) onSubmit;
  final Health health;
  final bool busy;
  final Brief? initial;

  @override
  State<Composer> createState() => ComposerState();
}

class ComposerState extends State<Composer> {
  late WorkFormat _format;
  final _title = TextEditingController();
  final _logline = TextEditingController();
  List<AnchorInput> _anchors = [];
  List<AnchorInput> _myComps = [];
  int _recency = 5;
  SizePref _size = SizePref.breakout;
  String _market = 'US';
  final Set<AgeBand> _ages = {};
  bool _more = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    load(widget.initial ?? const Brief(format: WorkFormat.book));
  }

  /// Fills the form from a brief (used by "try this example").
  void load(Brief b) {
    setState(() {
      _format = b.format;
      _title.text = b.title;
      _logline.text = b.logline;
      _anchors = [...b.anchors];
      _myComps = [...b.myComps];
      _recency = b.recencyYears;
      _size = b.size;
      _market = b.market;
      _ages
        ..clear()
        ..addAll(b.ages);
      _more = b.myComps.isNotEmpty;
      _error = null;
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _logline.dispose();
    super.dispose();
  }

  Brief get brief => Brief(
        format: _format,
        title: _title.text.trim(),
        logline: _logline.text.trim(),
        anchors: _anchors,
        myComps: _myComps,
        recencyYears: _format.recencyParam == null && _format != WorkFormat.game ? 0 : _recency,
        size: _size,
        market: _market,
        ages: _ages.toList()..sort((a, b) => a.index.compareTo(b.index)),
      );

  Future<void> _submit() async {
    final b = brief;
    final problems = b.problems();
    if (!widget.health.llm && b.anchors.isEmpty) {
      problems.insert(0, 'Add at least one touchstone — this server has no language model to read a description.');
    }
    if (problems.isNotEmpty) {
      setState(() => _error = problems.first);
      return;
    }
    setState(() => _error = null);
    await widget.onSubmit(b);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final phone = context.isPhone;
    final hasYear = _format.recencyParam != null || _format == WorkFormat.game;
    return Panel(
      padding: EdgeInsets.all(phone ? 16 : 26),
      radius: 22,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('What are you making?'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final f in WorkFormat.values) _formatChip(f)],
          ),
          const SizedBox(height: 22),
          _label('Working title', optional: true),
          const SizedBox(height: 8),
          TextField(
            controller: _title,
            maxLength: 120,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(hintText: 'e.g. The Lantern Archive', counterText: '', fillColor: c.paper),
          ),
          const SizedBox(height: 18),
          _label('What is it?', optional: widget.health.llm ? false : true),
          const SizedBox(height: 8),
          TextField(
            controller: _logline,
            minLines: 2,
            maxLines: 5,
            maxLength: 1200,
            decoration: InputDecoration(
              hintText: _loglineHint(_format),
              counterText: '',
            ),
          ),
          const SizedBox(height: 18),
          _label('It\'s like…'),
          const SizedBox(height: 4),
          Text(
            'Two to five things your audience already loves. Pick from Qloo\'s suggestions to pin the exact title.',
            style: context.t.bodySmall,
          ),
          const SizedBox(height: 10),
          TouchstoneField(
            values: _anchors,
            onChanged: (v) => setState(() => _anchors = v),
            kinds: [_format.primary, ..._format.cross],
            hint: _touchstoneHint(_format),
          ),
          const SizedBox(height: 14),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _more = !_more),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedRotation(
                    turns: _more ? 0.25 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(Icons.chevron_right_rounded, color: c.muted, size: 20),
                  ),
                  Text('Check my comps, size, recency, market', style: Fonts.sansW(14, FontWeight.w600, color: c.muted)),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !_more
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label('Comps you\'re planning to use', optional: true),
                        const SizedBox(height: 4),
                        Text('Meets will tell you which ones help and which ones hurt.', style: context.t.bodySmall),
                        const SizedBox(height: 10),
                        TouchstoneField(
                          values: _myComps,
                          onChanged: (v) => setState(() => _myComps = v),
                          kinds: [_format.primary],
                          hint: 'e.g. a bestseller everyone compares to',
                        ),
                        const SizedBox(height: 20),
                        _label('How big should comps be?'),
                        const SizedBox(height: 10),
                        _segmented<SizePref>(
                          values: SizePref.values,
                          selected: _size,
                          label: (s) => s.label,
                          onSelect: (s) => setState(() => _size = s),
                        ),
                        const SizedBox(height: 6),
                        Text(_size.help, style: context.t.bodySmall),
                        if (hasYear) ...[
                          const SizedBox(height: 20),
                          _label('How recent?'),
                          const SizedBox(height: 10),
                          _segmented<int>(
                            values: const [2, 3, 5, 8, 10, 0],
                            selected: _recency,
                            label: (y) => y == 0 ? 'Any year' : 'Last $y yrs',
                            onSelect: (y) => setState(() => _recency = y),
                          ),
                        ],
                        const SizedBox(height: 20),
                        Wrap(
                          spacing: 28,
                          runSpacing: 18,
                          children: [
                            SizedBox(
                              width: 240,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _label('Market'),
                                  const SizedBox(height: 8),
                                  DropdownButtonFormField<String>(
                                    initialValue: _market,
                                    isExpanded: true,
                                    borderRadius: BorderRadius.circular(12),
                                    items: [
                                      for (final m in Market.all) DropdownMenuItem(value: m.code, child: Text(m.name)),
                                    ],
                                    onChanged: (v) => setState(() => _market = v ?? 'US'),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _label('Audience age', optional: true),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    for (final a in AgeBand.values)
                                      FilterChip(
                                        label: Text(a.label),
                                        selected: _ages.contains(a),
                                        showCheckmark: false,
                                        selectedColor: c.ink,
                                        labelStyle: Fonts.sansW(13.5, FontWeight.w600,
                                            color: _ages.contains(a) ? c.paper : c.ink),
                                        onSelected: (on) => setState(() => on ? _ages.add(a) : _ages.remove(a)),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline_rounded, size: 18, color: c.danger),
                const SizedBox(width: 8),
                Expanded(child: Text(_error!, style: context.t.bodyMedium?.copyWith(color: c.danger))),
              ],
            ),
          ],
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.health.canBuild
                      ? 'Takes about 20–40 seconds. Every pick is measured in Qloo.'
                      : 'This server has no Qloo key, so only example kits are available.',
                  style: context.t.bodySmall,
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: widget.busy || !widget.health.canBuild ? null : _submit,
                icon: widget.busy
                    ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: c.onAccent))
                    : const Icon(Icons.arrow_forward_rounded, size: 18),
                label: const Text('Find my comps'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _label(String text, {bool optional = false}) {
    final c = context.c;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text, style: Fonts.sansW(14.5, FontWeight.w600, color: c.ink)),
        if (optional) ...[
          const SizedBox(width: 6),
          Text('optional', style: Fonts.monoW(11, color: c.faint)),
        ],
      ],
    );
  }

  Widget _formatChip(WorkFormat f) {
    final c = context.c;
    final selected = f == _format;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() {
          _format = f;
          if (f.recencyParam == null && f != WorkFormat.game) _recency = 0;
          if ((f.recencyParam != null || f == WorkFormat.game) && _recency == 0) _recency = 5;
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? c.ink : c.paper,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? c.ink : c.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(formatIcon(f), size: 17, color: selected ? c.paper : c.muted),
              const SizedBox(width: 8),
              Text(f.label, style: Fonts.sansW(14.5, FontWeight.w600, color: selected ? c.paper : c.ink)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _segmented<T>({
    required List<T> values,
    required T selected,
    required String Function(T) label,
    required ValueChanged<T> onSelect,
  }) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: c.paper, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.line)),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final v in values)
            InkWell(
              borderRadius: BorderRadius.circular(9),
              onTap: () => onSelect(v),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: v == selected ? c.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: v == selected ? c.line : Colors.transparent),
                  boxShadow: v == selected
                      ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))]
                      : null,
                ),
                child: Text(label(v),
                    style: Fonts.sansW(13.5, v == selected ? FontWeight.w700 : FontWeight.w500, color: v == selected ? c.ink : c.muted)),
              ),
            ),
        ],
      ),
    );
  }
}

String _loglineHint(WorkFormat f) => switch (f) {
      WorkFormat.book => 'One or two sentences: who, what goes wrong, why it matters.',
      WorkFormat.film => 'The logline: who, what they want, what stands in the way.',
      WorkFormat.tv => 'The series engine: the world, the people, the weekly problem.',
      WorkFormat.music => 'The sound and the feeling: genre, instruments, what it\'s about.',
      WorkFormat.game => 'The loop and the vibe: what you do, how it feels.',
      WorkFormat.podcast => 'The format: who hosts, what happens each episode.',
      WorkFormat.standup => 'Your voice: subjects, style, the kind of room you kill in.',
    };

String _touchstoneHint(WorkFormat f) => switch (f) {
      WorkFormat.book => 'e.g. Piranesi, The Starless Sea',
      WorkFormat.film => 'e.g. Palm Springs, Ready or Not',
      WorkFormat.tv => 'e.g. Ted Lasso, Abbott Elementary',
      WorkFormat.music => 'e.g. Japanese Breakfast, Beach House',
      WorkFormat.game => 'e.g. Slay the Spire, Spiritfarer',
      WorkFormat.podcast => 'e.g. How I Built This, Acquired',
      WorkFormat.standup => 'e.g. Nate Bargatze, Jim Gaffigan',
    };
