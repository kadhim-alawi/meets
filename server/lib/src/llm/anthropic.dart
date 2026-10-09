import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:meets_core/meets_core.dart';

/// A tool call the model asked for.
class ToolUse {
  const ToolUse(this.id, this.name, this.input);

  final String id;
  final String name;
  final Json input;
}

class LlmResponse {
  const LlmResponse({required this.content, required this.stopReason, required this.model, required this.usage});

  /// Raw content blocks, appended to the conversation unchanged (thinking
  /// blocks must be passed back as-is on the same model).
  final List<Json> content;
  final String stopReason;
  final String model;
  final Json usage;

  String get text => content.where((b) => b['type'] == 'text').map((b) => asString(b['text']) ?? '').join('\n').trim();

  List<ToolUse> get toolUses => content
      .where((b) => b['type'] == 'tool_use')
      .map((b) => ToolUse(asString(b['id']) ?? '', asString(b['name']) ?? '', asJson(b['input'])))
      .toList();
}

class LlmException implements Exception {
  LlmException(this.message, {this.status, this.refusal = false});

  final String message;
  final int? status;
  final bool refusal;

  @override
  String toString() => 'LLM error${status == null ? '' : ' ($status)'}: $message';
}

/// Minimal Claude Messages API client over raw HTTP (Dart has no official
/// Anthropic SDK). Opts into server-side refusal fallbacks by default.
class LlmClient {
  LlmClient({
    required String apiKey,
    this.model = 'claude-opus-5-5',
    this.effort = 'medium',
    String baseUrl = 'https://api.anthropic.com',
    http.Client? client,
    this.timeout = const Duration(seconds: 150),
  })  : _apiKey = apiKey,
        _base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl,
        _http = client ?? http.Client();

  final String _apiKey;
  final String _base;
  final http.Client _http;
  final String model;

  /// `low` | `medium` | `high` | `xhigh` | `max`.
  final String effort;
  final Duration timeout;

  int calls = 0;

  Future<LlmResponse> create({
    required String system,
    required List<Json> messages,
    List<Json> tools = const [],
    int maxTokens = 16000,
    String? effortOverride,
  }) async {
    final body = <String, dynamic>{
      'model': model,
      'max_tokens': maxTokens,
      'system': [
        {'type': 'text', 'text': system, 'cache_control': {'type': 'ephemeral'}},
      ],
      'messages': messages,
      'output_config': {'effort': effortOverride ?? effort},
      'fallbacks': 'default',
      if (tools.isNotEmpty) 'tools': tools,
      if (tools.isNotEmpty) 'tool_choice': {'type': 'auto'},
    };
    final headers = {
      'content-type': 'application/json',
      'x-api-key': _apiKey,
      'anthropic-version': '2023-06-01',
      'anthropic-beta': 'server-side-fallback-2026-07-01',
    };
    for (var attempt = 0;; attempt++) {
      calls++;
      http.Response res;
      try {
        res = await _http
            .post(Uri.parse('$_base/v1/messages'), headers: headers, body: jsonEncode(body))
            .timeout(timeout);
      } on TimeoutException {
        if (attempt < 1) continue;
        throw LlmException('timed out');
      } on http.ClientException catch (e) {
        if (attempt < 1) continue;
        throw LlmException('network error: ${e.message}');
      }
      final status = res.statusCode;
      if (status == 429 || status == 529 || status >= 500) {
        if (attempt < 2) {
          final retryAfter = double.tryParse(res.headers['retry-after'] ?? '');
          await Future<void>.delayed(Duration(milliseconds: ((retryAfter ?? (1.5 * (attempt + 1))) * 1000).round().clamp(500, 15000)));
          continue;
        }
      }
      final decoded = asJson(_tryDecode(res.body));
      if (status != 200) {
        final message = asString(asJson(decoded['error'])['message']) ?? 'HTTP $status';
        throw LlmException(message, status: status);
      }
      final response = LlmResponse(
        content: asList(decoded['content']).map(asJson).toList(),
        stopReason: asString(decoded['stop_reason']) ?? 'end_turn',
        model: asString(decoded['model']) ?? model,
        usage: asJson(decoded['usage']),
      );
      if (response.stopReason == 'refusal') {
        final category = asString(asJson(decoded['stop_details'])['category']);
        throw LlmException('the model declined this request${category == null ? '' : ' ($category)'}', refusal: true);
      }
      return response;
    }
  }

  static Object? _tryDecode(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }

  void close() => _http.close();
}

/// Builds a tool definition in the Messages API shape.
Json toolDef(String name, String description, Json properties, {List<String> required = const []}) => {
      'name': name,
      'description': description,
      'input_schema': {
        'type': 'object',
        'properties': properties,
        'required': required,
      },
    };

/// Pulls the first JSON object out of free text, for models that answer in
/// prose instead of calling the tool.
Json? extractJsonObject(String text) {
  final start = text.indexOf('{');
  final end = text.lastIndexOf('}');
  if (start < 0 || end <= start) return null;
  try {
    return asJson(jsonDecode(text.substring(start, end + 1)));
  } on FormatException {
    return null;
  }
}
