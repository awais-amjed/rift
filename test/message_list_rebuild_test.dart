import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart' as widgets;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/classes/chat_message.dart';
import 'package:rift/logic/cubits/app/app_cubit.dart';
import 'package:rift/logic/cubits/server_members/server_members_cubit.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/chat/chat_message_list.dart';
import 'package:rift/presentation/common/chat/message_row/chat_message_row.dart';

import 'support/stub_members_cubit.dart';

class _MemoryStorage implements Storage {
  final Map<String, dynamic> _data = {};

  @override
  dynamic read(String key) => _data[key];

  @override
  Future<void> write(String key, dynamic value) async => _data[key] = value;

  @override
  Future<void> delete(String key) async => _data.remove(key);

  @override
  Future<void> clear() async => _data.clear();

  @override
  Future<void> close() async {}
}

/// How much of the list a change to one message rebuilds.
///
/// The chat screen rebuilds the list for every change to the conversation —
/// an upload's progress many times a second, a reaction, a message arriving —
/// and hands it fresh callbacks each time, as a surface does. A row whose
/// message did not change has nothing new to draw, and rebuilding every row
/// on screen for each tick is what made a picture's loader look new.
void main() {
  setUpAll(() => HydratedBloc.storage = _MemoryStorage());

  final base = DateTime.utc(2026, 1, 1, 12);

  ChatMessage msg(int i) => ChatMessage(
    id: '$i',
    authorId: i.isEven ? 'a' : 'b',
    authorName: i.isEven ? 'Ana' : 'Ben',
    text: 'message $i',
    sentAt: base.add(Duration(seconds: i)),
    isMine: false,
  );

  Future<void> pump(
    WidgetTester tester,
    List<ChatMessage> messages, {
    void Function(ChatMessage)? onReply,
    bool canReact = true,
  }) {
    return tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<ThemeCubit>(create: (_) => ThemeCubit()),
          BlocProvider<AppCubit>(create: (_) => AppCubit()),
          BlocProvider<ServerMembersCubit>(create: (_) => StubMembersCubit()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ChatMessageList(
              key: const ValueKey('list'),
              messages: messages,
              // New closures and a new set on every pump, the way a chat
              // screen builds them.
              onReply: onReply ?? (m) {},
              canReact: canReact,
              onForward: (m) {},
              onReport: (m) {},
              onTogglePin: (m) {},
              onOpenProfile: (id, name) {},
              onToggleReaction: (id, emoji) {},
              mentionable: {'all'},
            ),
          ),
        ),
      ),
    );
  }

  /// Rows built while [body] runs.
  Future<int> rowBuilds(Future<void> Function() body) async {
    var n = 0;
    widgets.debugOnRebuildDirtyWidget = (element, builtOnce) {
      if (element.widget is ChatMessageRow) n++;
    };
    try {
      await body();
    } finally {
      widgets.debugOnRebuildDirtyWidget = null;
    }
    return n;
  }

  testWidgets('a change to one message rebuilds that row only', (
    tester,
  ) async {
    final messages = [for (var i = 1; i <= 12; i++) msg(i)];
    await pump(tester, messages);
    final changed = [...messages];
    changed[11] = messages[11].copyWith(text: 'edited');
    final n = await rowBuilds(() => pump(tester, changed));
    expect(n, 1);
  });

  testWidgets('a rebuild with nothing changed rebuilds no row', (tester) async {
    final messages = [for (var i = 1; i <= 12; i++) msg(i)];
    await pump(tester, messages);
    final n = await rowBuilds(() => pump(tester, [...messages]));
    expect(n, 0);
  });

  testWidgets('a kept row calls the newest callback', (tester) async {
    final messages = [for (var i = 1; i <= 3; i++) msg(i)];
    final calls = <String>[];
    await pump(tester, messages, onReply: (m) => calls.add('old'));
    await pump(tester, [...messages], onReply: (m) => calls.add('new'));
    final row = tester.widget<ChatMessageRow>(find.byType(ChatMessageRow).last);
    row.onReply!(row.message);
    expect(calls, ['new']);
  });

  testWidgets('a change every row draws from rebuilds them all', (
    tester,
  ) async {
    final messages = [for (var i = 1; i <= 12; i++) msg(i)];
    await pump(tester, messages);
    final n = await rowBuilds(() => pump(tester, messages, canReact: false));
    expect(n, 12);
  });

  testWidgets('a message arriving builds its own row only', (tester) async {
    final messages = [for (var i = 1; i <= 12; i++) msg(i)];
    await pump(tester, messages);
    final n = await rowBuilds(() => pump(tester, [...messages, msg(13)]));
    expect(n, 1);
  });
}
