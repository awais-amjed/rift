import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The runner keeps one sink for `rift/ptt_keys`. A second
/// `receiveBroadcastStream` on it would take the sink over, and push-to-talk
/// or the call shortcuts would quietly stop hearing keys in the background.
void main() {
  test('only WindowsKeyHook opens the ptt channel', () {
    final opening = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => f.readAsStringSync().contains("'rift/ptt_keys'"))
        .map((f) => f.path.replaceAll(r'\', '/'))
        .toList();
    expect(opening, ['lib/logic/ptt/windows_key_hook.dart']);
  });
}
