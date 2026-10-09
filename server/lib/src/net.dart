import 'dart:io';

import 'package:shelf/shelf.dart';

/// How many reverse proxies in front of the server append to
/// `X-Forwarded-For`. The client's address is that many entries from the
/// right; anything further left was written by the client and can't be
/// trusted. Render and most single-proxy hosts: 1. Google Cloud Run: 2.
int trustedProxyHops = 1;

/// The caller's IP for rate limiting.
String clientIp(Request request) {
  // Fly.io sets this itself; clients can't spoof it through Fly's edge.
  final fly = request.headers['fly-client-ip'];
  if (fly != null && fly.isNotEmpty) return fly.trim();
  final forwarded = request.headers['x-forwarded-for'];
  if (forwarded != null && forwarded.isNotEmpty && trustedProxyHops > 0) {
    final parts = forwarded.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (parts.isNotEmpty) return parts[(parts.length - trustedProxyHops).clamp(0, parts.length - 1)];
  }
  final info = request.context['shelf.io.connection_info'];
  return info is HttpConnectionInfo ? info.remoteAddress.address : 'unknown';
}
