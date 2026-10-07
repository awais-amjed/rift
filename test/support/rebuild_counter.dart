import 'package:flutter/widgets.dart';

/// How many times each kind of widget rebuilt while [body] ran, counting a
/// rebuild its parent caused as well as one it asked for itself.
///
/// For tests that pin down how much a change redraws. Debug builds only,
/// which is what `flutter test` runs.
Future<Map<Type, int>> countRebuilds(Future<void> Function() body) async {
  final counts = <Type, int>{};
  debugOnRebuildDirtyWidget = (element, builtOnce) {
    final type = element.widget.runtimeType;
    counts[type] = (counts[type] ?? 0) + 1;
  };
  try {
    await body();
  } finally {
    debugOnRebuildDirtyWidget = null;
  }
  return counts;
}
