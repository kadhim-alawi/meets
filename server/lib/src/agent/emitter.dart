import 'package:meets_core/meets_core.dart';

import '../qloo/qloo_client.dart';

/// Receives what the agent is doing, for the live timeline and audit trail.
abstract class Emitter {
  void emit(String kind, String title, {String? detail, Json data = const {}});

  void step(String title, [String? detail]) => emit('step', title, detail: detail);
  void decision(String title, [String? detail]) => emit('decision', title, detail: detail);
  void warn(String title, [String? detail]) => emit('warn', title, detail: detail);
  void llm(String title, {String? detail, Json data = const {}}) => emit('llm', title, detail: detail, data: data);

  void qloo(QlooCall call, {required String label, int? count}) => emit(
        'qloo',
        label,
        detail: call.error,
        data: compact({
          'path': call.path,
          'params': call.params,
          'status': call.status,
          'ms': call.ms,
          'cached': call.cached ? true : null,
          'count': count,
        }),
      );
}

/// Collects events in memory. Used by runs, tests and the MCP endpoint.
class ListEmitter extends Emitter {
  ListEmitter({this.onEvent});

  final List<RunEvent> events = [];
  final void Function(RunEvent event)? onEvent;
  int _seq = 0;

  @override
  void emit(String kind, String title, {String? detail, Json data = const {}}) {
    final event = RunEvent(seq: ++_seq, at: DateTime.now().toUtc(), kind: kind, title: title, detail: detail, data: data);
    events.add(event);
    onEvent?.call(event);
  }

  int get qlooCalls => events.where((e) => e.kind == 'qloo').length;
  int get cachedCalls => events.where((e) => e.kind == 'qloo' && e.data['cached'] == true).length;
  int get llmCalls => events.where((e) => e.kind == 'llm' && e.data['call'] == true).length;
}
