import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every call in `data/apis` is bound to the server it names
/// (`ServerSession`), and nothing there falls back on the one on screen.
///
/// That fallback is how a call kept running on one server sent its key, its
/// avatars and its moderation to the server being read, and how a dialog
/// about one server wrote to another: a `serverId` left out meant "the
/// selected one", and nothing said it had been left out.
void main() {
  final apis = [
    for (final file in Directory('lib/data/apis').listSync())
      if (file is File && file.path.endsWith('.dart')) file,
  ];

  String code(File file) => file
      .readAsStringSync()
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('//'))
      .join('\n');

  test('no call reads the selection', () {
    final reads = RegExp(r'\bselectedServer(Id)?\b|\bcallSelected\b');
    expect([
      for (final file in apis)
        if (reads.hasMatch(code(file))) file.path,
    ], isEmpty);
  });

  test('no call takes an optional server', () {
    final optional = RegExp(r'String\? serverId\b');
    expect([
      for (final file in apis)
        if (optional.hasMatch(code(file))) file.path,
    ], isEmpty);
  });

  test('every class is built on a bound server, or says why not', () {
    // Before there is a server to be signed in to: creating one, and reading
    // an invite to it.
    const unbound = {'joining_api.dart'};
    final constructor = RegExp(r'^  \w+Api\(this\._target\b', multiLine: true);
    expect([
      for (final file in apis)
        if (!unbound.contains(file.uri.pathSegments.last) &&
            !constructor.hasMatch(file.readAsStringSync()))
          file.path,
    ], isEmpty);
  });
}
