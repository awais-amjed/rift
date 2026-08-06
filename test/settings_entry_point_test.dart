import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every widget that navigates to the settings screen.
List<String> _settingsCallers() {
  final callers = <String>[];
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final source = entity.readAsStringSync();
    // The route constant's own declaration is not a caller.
    if (source.contains('AppRoutes.settings')) callers.add(entity.path);
  }
  return callers..sort();
}

void main() {
  test('settings has exactly one way in, from the rail', () {
    final callers = _settingsCallers();

    // A second button opening the same screen reads as a different
    // destination, and the two drift apart the moment one of them grows a
    // condition the other doesn't. The path isn't pinned — moving the rail is
    // fine, adding a second door is not.
    expect(callers, hasLength(1), reason: 'opens settings: $callers');
    expect(callers.single, contains('server_rail'));
  });
}
