import 'dart:io';

/// Server settings, all from environment variables (see `.env.example`).
class Config {
  Config({
    required this.port,
    required this.host,
    required this.qlooKey,
    required this.qlooBaseUrl,
    required this.qlooMode,
    required this.anthropicKey,
    required this.anthropicBaseUrl,
    required this.llmModel,
    required this.llmEffort,
    required this.dataDir,
    required this.webDir,
    required this.examplesDir,
    required this.publicUrl,
    required this.runsPerHourPerIp,
    required this.runsPerDay,
    required this.maxConcurrentRuns,
    required this.qlooMinIntervalMs,
    this.trustedProxyHops = 1,
  });

  final int port;
  final String host;
  final String qlooKey;
  final String qlooBaseUrl;

  /// `live` (needs [qlooKey]), `preview` (labelled sample data) or `off`.
  final String qlooMode;
  final String anthropicKey;
  final String anthropicBaseUrl;
  final String llmModel;
  final String llmEffort;
  final String dataDir;
  final String webDir;
  final String examplesDir;
  final String publicUrl;
  final int runsPerHourPerIp;
  final int runsPerDay;
  final int maxConcurrentRuns;
  final int qlooMinIntervalMs;

  /// Proxies that append to X-Forwarded-For (see `net.dart`).
  final int trustedProxyHops;

  bool get llmEnabled => anthropicKey.isNotEmpty;

  static Config fromEnvironment([Map<String, String>? env]) {
    final e = env ?? Platform.environment;
    String s(String key, String fallback) {
      final v = e[key]?.trim();
      return v == null || v.isEmpty ? fallback : v;
    }

    int i(String key, int fallback) => int.tryParse(e[key] ?? '') ?? fallback;
    final key = s('QLOO_API_KEY', '');
    final requested = s('QLOO_MODE', key.isEmpty ? 'off' : 'live').toLowerCase();
    return Config(
      port: i('PORT', 8080),
      host: s('HOST', '0.0.0.0'),
      qlooKey: key,
      qlooBaseUrl: s('QLOO_BASE_URL', 'https://hackathon.api.qloo.com'),
      qlooMode: requested == 'live' && key.isEmpty ? 'off' : requested,
      anthropicKey: s('ANTHROPIC_API_KEY', ''),
      // Deliberately not ANTHROPIC_BASE_URL, so a developer's shell setting
      // for other tools never redirects the app's traffic.
      anthropicBaseUrl: s('MEETS_ANTHROPIC_BASE_URL', 'https://api.anthropic.com'),
      llmModel: s('LLM_MODEL', 'claude-sonnet-5-5'),
      llmEffort: s('LLM_EFFORT', 'medium'),
      dataDir: s('DATA_DIR', 'data'),
      webDir: s('WEB_DIR', '../app/build/web'),
      examplesDir: s('EXAMPLES_DIR', 'examples'),
      publicUrl: s('PUBLIC_URL', ''),
      runsPerHourPerIp: i('RUNS_PER_HOUR_PER_IP', 20),
      runsPerDay: i('RUNS_PER_DAY', 400),
      maxConcurrentRuns: i('MAX_CONCURRENT_RUNS', 4),
      qlooMinIntervalMs: i('QLOO_MIN_INTERVAL_MS', 260),
      trustedProxyHops: i('TRUSTED_PROXY_HOPS', 1),
    );
  }
}
