import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Flutter 3.41 turned the hand cursor off for `InkWell` on desktop, and an
/// `InkWell` has no theme to turn it back on from — so every one in `lib/`
/// asks for it as its first argument, and this catches the one that forgets.
void main() {
  test('every InkWell asks for the hand cursor', () {
    final call = RegExp(
      r'^(?!\s*//).*\b(InkWell|InkResponse)\(',
      multiLine: true,
    );
    final missing = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final source = file.readAsStringSync();
      for (final match in call.allMatches(source)) {
        if (!source
            .substring(match.end)
            .trimLeft()
            .startsWith('mouseCursor:')) {
          final line =
              '\n'.allMatches(source.substring(0, match.end)).length + 1;
          missing.add('${file.path}:$line');
        }
      }
    }
    expect(missing, isEmpty);
  });
}
