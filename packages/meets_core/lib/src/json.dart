/// Small helpers for reading loosely typed JSON without throwing.
library;

typedef Json = Map<String, dynamic>;

Json asJson(Object? value) =>
    value is Map ? value.map((k, v) => MapEntry(k.toString(), v)) : <String, dynamic>{};

List<dynamic> asList(Object? value) => value is List ? value : const [];

String? asString(Object? value) {
  if (value == null) return null;
  if (value is String) return value.isEmpty ? null : value;
  return value.toString();
}

double? asDouble(Object? value) {
  if (value is num) return value.isFinite ? value.toDouble() : null;
  if (value is String) return double.tryParse(value);
  return null;
}

int? asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.isFinite ? value.round() : null;
  if (value is String) return int.tryParse(value) ?? double.tryParse(value)?.round();
  return null;
}

bool asBool(Object? value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value is String) return value == 'true';
  return fallback;
}

List<T> listOf<T>(Object? value, T Function(Json) parse) =>
    asList(value).whereType<Map>().map((e) => parse(asJson(e))).toList();

List<String> stringsOf(Object? value) =>
    asList(value).map(asString).whereType<String>().toList();

/// Drops null values and empty collections so payloads stay small.
Json compact(Json map) {
  map.removeWhere((_, v) => v == null || (v is Iterable && v.isEmpty) || (v is Map && v.isEmpty));
  return map;
}
