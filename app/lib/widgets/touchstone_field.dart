import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:meets_core/meets_core.dart';

import '../api.dart';
import '../theme.dart';
import 'common.dart';

/// Chip input with live Qloo search. Picking a suggestion pins the exact
/// Qloo entity; pressing Enter keeps free text for the agent to resolve.
class TouchstoneField extends StatefulWidget {
  const TouchstoneField({
    super.key,
    required this.values,
    required this.onChanged,
    required this.kinds,
    required this.hint,
    this.max = 8,
    this.enabled = true,
  });

  final List<AnchorInput> values;
  final ValueChanged<List<AnchorInput>> onChanged;
  final List<EntityKind> kinds;
  final String hint;
  final int max;
  final bool enabled;

  @override
  State<TouchstoneField> createState() => _TouchstoneFieldState();
}

class _TouchstoneFieldState extends State<TouchstoneField> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _link = LayerLink();
  final _portal = OverlayPortalController();
  Timer? _debounce;
  List<Entity> _results = const [];
  bool _loading = false;
  int _highlight = 0;
  int _query = 0;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) {
        Future<void>.delayed(const Duration(milliseconds: 180), () {
          if (mounted && !_focus.hasFocus) _portal.hide();
        });
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onText(String text) {
    _debounce?.cancel();
    final q = text.trim();
    if (q.length < 2) {
      setState(() => _results = const []);
      _portal.hide();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 280), () async {
      final id = ++_query;
      setState(() => _loading = true);
      _portal.show();
      try {
        final results = await Api.instance.search(q, widget.kinds);
        if (!mounted || id != _query) return;
        setState(() {
          _results = results.where((r) => !widget.values.any((v) => v.id == r.id)).take(7).toList();
          _highlight = 0;
          _loading = false;
        });
      } on Object {
        if (!mounted || id != _query) return;
        setState(() {
          _results = const [];
          _loading = false;
        });
      }
    });
  }

  void _add(AnchorInput input) {
    if (widget.values.length >= widget.max) return;
    if (widget.values.any((v) => v.name.toLowerCase() == input.name.toLowerCase() && v.id == input.id)) return;
    widget.onChanged([...widget.values, input]);
    _controller.clear();
    setState(() => _results = const []);
    _portal.hide();
    _focus.requestFocus();
  }

  void _addTyped() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    if (_results.isNotEmpty && _portal.isShowing) {
      final e = _results[_highlight.clamp(0, _results.length - 1)];
      _add(AnchorInput(name: e.name, kind: e.kind, id: e.id));
    } else {
      _add(AnchorInput(name: text));
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown && _results.isNotEmpty) {
      setState(() => _highlight = (_highlight + 1) % _results.length);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp && _results.isNotEmpty) {
      setState(() => _highlight = (_highlight - 1 + _results.length) % _results.length);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _portal.hide();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace && _controller.text.isEmpty && widget.values.isNotEmpty) {
      widget.onChanged(widget.values.sublist(0, widget.values.length - 1));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final full = widget.values.length >= widget.max;
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) => _overlay(context),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: BoxDecoration(
            color: c.paper,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _focus.hasFocus ? c.ink : c.line, width: _focus.hasFocus ? 1.4 : 1),
          ),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final v in widget.values) _chip(v),
              if (!full)
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 200, maxWidth: 520),
                  child: IntrinsicWidth(
                    child: Focus(
                      onKeyEvent: _onKey,
                      child: TextField(
                        controller: _controller,
                        focusNode: _focus,
                        enabled: widget.enabled,
                        onChanged: _onText,
                        onSubmitted: (_) => _addTyped(),
                        onTap: () => setState(() {}),
                        textInputAction: TextInputAction.done,
                        style: context.t.bodyMedium,
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: widget.values.isEmpty ? widget.hint : 'Add another…',
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(AnchorInput v) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: v.id != null ? c.teal.withValues(alpha: 0.5) : c.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(v.kind == null ? Icons.edit_outlined : kindIcon(v.kind!), size: 14, color: v.id != null ? c.teal : c.muted),
          const SizedBox(width: 6),
          Text(v.name, style: Fonts.sansW(14, FontWeight.w500, color: c.ink)),
          const SizedBox(width: 2),
          InkResponse(
            radius: 14,
            onTap: widget.enabled ? () => widget.onChanged(widget.values.where((x) => !identical(x, v)).toList()) : null,
            child: Padding(padding: const EdgeInsets.all(3), child: Icon(Icons.close_rounded, size: 15, color: c.faint)),
          ),
        ],
      ),
    );
  }

  Widget _overlay(BuildContext context) {
    final c = context.c;
    final box = this.context.findRenderObject() as RenderBox?;
    final width = box?.size.width ?? 420;
    return Positioned(
      width: width.clamp(280, 640),
      child: CompositedTransformFollower(
        link: _link,
        targetAnchor: Alignment.bottomLeft,
        offset: const Offset(0, 6),
        child: TextFieldTapRegion(
          child: Material(
            color: c.surface,
            elevation: 10,
            shadowColor: Colors.black.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              constraints: const BoxConstraints(maxHeight: 380),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: c.line)),
              child: _loading && _results.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(children: [
                        SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: c.accent)),
                        const SizedBox(width: 10),
                        Text('Searching Qloo…', style: context.t.bodySmall),
                      ]),
                    )
                  : ListView(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      shrinkWrap: true,
                      children: [
                        for (var i = 0; i < _results.length; i++) _option(_results[i], i == _highlight),
                        InkWell(
                          onTap: () => _add(AnchorInput(name: _controller.text.trim())),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            child: Text('Use "${_controller.text.trim()}" as typed — Meets will look it up',
                                style: context.t.bodySmall),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _option(Entity e, bool highlighted) {
    final c = context.c;
    final meta = [e.kind.label, if (e.year != null) '${e.year}', if (e.creator != null) e.creator!].join(' · ');
    return InkWell(
      onTap: () => _add(AnchorInput(name: e.name, kind: e.kind, id: e.id)),
      child: Container(
        color: highlighted ? c.surfaceAlt : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Cover(entity: e, width: 32, height: 44, radius: 4),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.t.titleSmall),
                  const SizedBox(height: 2),
                  Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.t.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
