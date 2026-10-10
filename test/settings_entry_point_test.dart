import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every widget that navigates to the settings screen.
List<String> _settingsCallers() {
  final callers = <String>[];
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final source = entity.readAsStringSync();
    // The route constant's own declaration is not a caller. Nor is a link
    // to one section (a `SettingsTarget`), such as the ducking notice's
    // "Fix it": that is a shortcut to a place, not another door to the
    // screen.
    if (source.contains('AppRoutes.settings') &&
        !source.contains('SettingsTarget(')) {
      callers.add(entity.path);
    }
  }
  return callers..sort();
}

void main() {
  test('settings has one way in per shell', () {
    final callers = _settingsCallers();

    // A second button opening the same screen reads as a different
    // destination, and the two drift apart the moment one of them grows a
    // condition the other doesn't. A desktop has the rail's gear; a phone has
    // no rail, so its gear is on the dock at the foot of the switcher — which
    // is only offered there. The paths aren't pinned; a third door is the bug.
    expect(callers, hasLength(2), reason: 'opens settings: $callers');
    expect(callers.any((c) => c.contains('server_rail')), isTrue);
    expect(callers.any((c) => c.contains('user_dock')), isTrue);
  });
}
