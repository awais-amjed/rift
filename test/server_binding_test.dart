import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every call in `data/apis` is bound to the server it names
/// (`ServerSession`), and nothing there falls back on the one on screen.
/// Above it, a cubit keeps the server it was given and a widget asks its
/// `ServerScope`; only the places that choose or show the selection read it.
///
/// That fallback is how a call kept running on one server sent its key, its
/// avatars and its moderation to the server being read, and how a dialog
/// about one server wrote to another: a `serverId` left out meant "the
/// selected one", and nothing said it had been left out.
void main() {
  List<File> dartFiles(String dir) => [
    for (final file in Directory(dir).listSync(recursive: true))
      if (file is File &&
          file.path.endsWith('.dart') &&
          !file.path.endsWith('.g.dart'))
        file,
  ];

  final apis = dartFiles('lib/data/apis');

  String code(File file) => file
      .readAsStringSync()
      .split('\n')
      .where((line) => !line.trimLeft().startsWith('//'))
      .join('\n');

  String path(File file) => file.path.replaceAll(r'\', '/');

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

  test('no cubit queries a database itself', () {
    // A query on a raw client skips `ServerSession.call`, so a token the
    // server refuses is never signed in again: the notifications cubit's
    // badges and read marks did this on its Realtime client until Oct 23.
    final query = RegExp(r"\.rpc\(|\.from\('");
    expect([
      for (final file in dartFiles('lib/logic/cubits'))
        if (query.hasMatch(code(file))) file.path,
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

  test('below the server list, only the hub reads the selection', () {
    // Each with the reason it is about the selection itself.
    const allowed = {
      // It is the selection.
      'lib/logic/cubits/server/',
      // It keeps the copy everything below reads, and says when it moves.
      'lib/data/repositories/session_repository.dart',
      // It holds the selected server's context, and names the selected
      // server to what shows its conversations (the open channel, DMs).
      'lib/logic/services/server_hub.dart',
      // Its banner says the server on screen cannot be reached.
      'lib/logic/cubits/server_reach/server_reach_cubit.dart',
    };
    final reads = RegExp(r'\bselectedServer(Id)?\b');
    expect([
      for (final file in [...dartFiles('lib/logic'), ...dartFiles('lib/data')])
        if (!allowed.any(path(file).startsWith) && reads.hasMatch(code(file)))
          file.path,
    ], isEmpty);
  });

  test('a widget asks its scope which server it is about', () {
    // The places that choose the selection, mark it, or put it into a scope.
    const allowed = {
      'lib/presentation/common/selected_server_scope.dart',
      // Before a call, the call's surfaces are about the selected server.
      'lib/presentation/common/call_server_scope.dart',
      'lib/presentation/screens/home/home_screen.dart',
      'lib/presentation/screens/home/servers/server_rail/widgets/rail_server_list.dart',
      'lib/presentation/screens/home/mobile/switcher/server_switcher_sheet.dart',
      'lib/presentation/screens/home/mobile/switcher/switcher_server_list.dart',
      'lib/presentation/screens/home/mobile/switcher/switcher_server_row.dart',
      // Each switches to the server what it opens is on.
      'lib/presentation/screens/home/conversation_notification_router.dart',
      'lib/presentation/screens/home/dms/open_server_dm.dart',
      'lib/presentation/screens/home/calls/open_call_conversation.dart',
      'lib/presentation/screens/home/main_content/widgets/call_resumer.dart',
      'lib/presentation/screens/home/profile/user_dock/widgets/dock_call_panel.dart',
    };
    // The getter with its fall back to the first server: nowhere at all.
    final fallback = RegExp(r'\bselectedServer\b');
    final reads = RegExp(r'\bselectedServerId\b');
    expect([
      for (final file in dartFiles('lib/presentation'))
        if (fallback.hasMatch(code(file)) ||
            (!allowed.contains(path(file)) && reads.hasMatch(code(file))))
          file.path,
    ], isEmpty);
  });
}
