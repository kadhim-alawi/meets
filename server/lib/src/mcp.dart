import 'dart:convert';

import 'package:meets_core/meets_core.dart';
import 'package:shelf/shelf.dart';

import 'agent/comps_agent.dart';
import 'agent/emitter.dart';
import 'qloo/qloo_client.dart';
import 'runs.dart';

/// A minimal Model Context Protocol endpoint (Streamable HTTP, JSON
/// responses) so any MCP-capable agent can use Meets as a tool.
class McpEndpoint {
  McpEndpoint({required this.runs, required this.publicUrl});

  final RunManager runs;
  final String publicUrl;

  static const _protocol = '2025-06-18';

  static final _briefProps = {
    'format': {
      'type': 'string',
      'enum': WorkFormat.values.map((f) => f.name).toList(),
      'description': 'What is being made.',
    },
    'touchstones': {
      'type': 'array',
      'items': {'type': 'string'},
      'description': 'Existing works, artists or people the audience already loves (exact titles).',
    },
    'logline': {'type': 'string', 'description': 'One or two sentences about the project.'},
    'title': {'type': 'string'},
    'market': {'type': 'string', 'description': 'Market code, e.g. US, GB, IN. Default US.'},
    'recency_years': {'type': 'integer', 'description': 'How recent comps should be. Default 5; 0 = any.'},
    'size': {'type': 'string', 'enum': ['indie', 'breakout', 'mainstream']},
  };

  static final tools = [
    {
      'name': 'find_comps',
      'description': 'Find right-sized, recent comparable titles ("comps") and the likely audience for a creative work '
          '(book, film, TV, music, game, podcast, stand-up), measured with Qloo taste data. Returns the comp line, '
          'ranked comps with fit and size, audience skew, markets and a link to the full kit.',
      'inputSchema': {
        'type': 'object',
        'properties': _briefProps,
        'required': ['format', 'touchstones'],
      },
    },
    {
      'name': 'check_comps',
      'description': 'Check comps a creator plans to use: flags ones that are too big, too old or a weak audience fit, '
          'and suggests right-sized swaps, using Qloo taste data.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          ..._briefProps,
          'comps': {'type': 'array', 'items': {'type': 'string'}, 'description': 'The comps to check.'},
        },
        'required': ['format', 'touchstones', 'comps'],
      },
    },
  ];

  Future<Response> handle(Request request) async {
    if (request.method != 'POST') {
      return Response(405, body: 'Use POST with JSON-RPC 2.0.', headers: {'allow': 'POST'});
    }
    Object? body;
    try {
      body = jsonDecode(await request.readAsString());
    } on FormatException {
      return _json(_error(null, -32700, 'Parse error'));
    }
    if (body is List) {
      final results = <Object>[];
      for (final item in body) {
        final r = await _dispatch(asJson(item), request);
        if (r != null) results.add(r);
      }
      return results.isEmpty ? Response(202) : _json(results);
    }
    final result = await _dispatch(asJson(body), request);
    return result == null ? Response(202) : _json(result);
  }

  Response _json(Object body) => Response.ok(jsonEncode(body), headers: {'content-type': 'application/json'});

  Json _error(Object? id, int code, String message) => {
        'jsonrpc': '2.0',
        'id': id,
        'error': {'code': code, 'message': message},
      };

  Json _result(Object? id, Object result) => {'jsonrpc': '2.0', 'id': id, 'result': result};

  Future<Json?> _dispatch(Json msg, Request request) async {
    final id = msg['id'];
    final method = asString(msg['method']);
    if (method == null) return _error(id, -32600, 'Invalid request');
    if (id == null) return null; // notification, e.g. notifications/initialized
    switch (method) {
      case 'initialize':
        return _result(id, {
          'protocolVersion': _protocol,
          'capabilities': {'tools': {}},
          'serverInfo': {'name': 'meets', 'version': '1.0.0'},
          'instructions': 'Meets finds comps and audiences for creative work with Qloo taste data. Call find_comps with a format and 1-5 touchstones.',
        });
      case 'ping':
        return _result(id, {});
      case 'tools/list':
        return _result(id, {'tools': tools});
      case 'tools/call':
        final params = asJson(msg['params']);
        return _result(id, await _call(asString(params['name']) ?? '', asJson(params['arguments']), request));
      default:
        return _error(id, -32601, 'Method not found: $method');
    }
  }

  Brief _brief(Json args) => Brief(
        format: WorkFormat.fromName(asString(args['format'])),
        title: asString(args['title']) ?? '',
        logline: asString(args['logline']) ?? '',
        anchors: stringsOf(args['touchstones']).take(8).map((n) => AnchorInput(name: n)).toList(),
        myComps: stringsOf(args['comps']).take(8).map((n) => AnchorInput(name: n)).toList(),
        market: (asString(args['market']) ?? 'US').toUpperCase(),
        recencyYears: asInt(args['recency_years']) ?? 5,
        size: SizePref.fromName(asString(args['size'])),
      );

  Future<Json> _call(String name, Json args, Request request) async {
    if (name != 'find_comps' && name != 'check_comps') {
      return {'isError': true, 'content': [{'type': 'text', 'text': 'Unknown tool $name'}]};
    }
    final brief = _brief(args);
    final problems = brief.problems();
    if (brief.anchors.isEmpty) problems.add('Give at least one touchstone.');
    if (problems.isNotEmpty) {
      return {'isError': true, 'content': [{'type': 'text', 'text': problems.join(' ')}]};
    }
    final ip = request.headers['x-forwarded-for']?.split(',').first.trim() ?? 'mcp';
    final emitter = ListEmitter();
    try {
      runs.reserve(ip);
      final kitId = newId(8);
      final kit = await runs.withSlot(() => CompsAgent(client: runs.client, llm: runs.llm).build(brief, emitter, kitId: kitId));
      await runs.kits.save(kit, emitter.events);
      final link = publicUrl.isEmpty ? null : '$publicUrl/kit/${kit.id}';
      return {
        'content': [
          {'type': 'text', 'text': _summaryText(kit, link, checkOnly: name == 'check_comps')},
        ],
        'structuredContent': _structured(kit, link),
      };
    } on AgentFailure catch (e) {
      return {'isError': true, 'content': [{'type': 'text', 'text': e.message}]};
    } on QlooException catch (e) {
      return {'isError': true, 'content': [{'type': 'text', 'text': 'Qloo error: ${e.message}'}]};
    } on LimitExceeded catch (e) {
      return {'isError': true, 'content': [{'type': 'text', 'text': e.message}]};
    }
  }

  String _summaryText(CompKit kit, String? link, {bool checkOnly = false}) {
    final out = StringBuffer();
    if (kit.mode == 'preview') out.writeln('[PREVIEW DATA - not from Qloo]');
    if (!checkOnly) {
      if (kit.pairing != null) out.writeln('Comp line: ${kit.pairing!.line}');
      if (kit.headline != null) out.writeln(kit.headline);
      out.writeln('\nComps (${kit.brief.format.primary.plural.toLowerCase()}):');
      for (final c in rankForDisplay(kit.primary.items).take(8)) {
        final e = c.entity;
        out.writeln('- ${e.name}${e.year == null ? '' : ' (${e.year})'}: fit ${(c.fit * 100).round()}, ${c.size.label} '
            '(${topPercentLabel(e.popularity)})${c.flags.isEmpty ? '' : ', ${c.flags.map(flagLabel).join(', ')}'}');
      }
      final audience = kit.audience;
      if (audience != null && !audience.isEmpty) out.writeln('\n${describeAudience(audience, kit.brief.format.audience)}');
      if (kit.markets.isNotEmpty) out.writeln('Markets: ${kit.markets.take(5).map((m) => m.name).join(', ')}');
    }
    if (kit.compCheck.isNotEmpty) {
      out.writeln('\nComp check:');
      for (final v in kit.compCheck) {
        out.writeln('- ${v.input}: ${v.verdict}. ${v.reasons.join(' ')}${v.swap == null ? '' : ' Swap: ${v.swap!.entity.name}.'}');
      }
    }
    if (link != null) out.writeln('\nFull kit: $link');
    return out.toString().trim();
  }

  Json _structured(CompKit kit, String? link) => compact({
        'kitId': kit.id,
        'url': link,
        'mode': kit.mode,
        'compLine': kit.pairing?.line,
        'comps': rankForDisplay(kit.primary.items)
            .take(10)
            .map((c) => compact({
                  'name': c.entity.name,
                  'year': c.entity.year,
                  'fit': double.parse(c.fit.toStringAsFixed(3)),
                  'size': c.size.label,
                  'flags': c.flags,
                }))
            .toList(),
        'compCheck': kit.compCheck.map((v) => compact({'input': v.input, 'verdict': v.verdict, 'swap': v.swap?.entity.name})).toList(),
      });
}
