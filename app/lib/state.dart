import 'package:flutter/foundation.dart';
import 'package:meets_core/meets_core.dart';

/// The last brief the user submitted, so "edit brief" can bring it back.
final ValueNotifier<Brief?> lastBrief = ValueNotifier<Brief?>(null);

/// A finished run handed from the run screen to the kit screen, so the kit
/// does not have to be fetched again.
class KitHandoff {
  const KitHandoff(this.kit, this.trace);

  final CompKit kit;
  final List<RunEvent> trace;
}
