import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rift/logic/cubits/app/app_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/classes/chat_message.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/logic/services/chat_message_ops.dart';
import 'package:rift/presentation/common/chat/chat_message_list.dart';
import 'package:rift/presentation/common/chat/message_row/chat_message_row.dart';

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

/// Which messages animate on their way in, and which appear already there.
///
/// Three ways a row shows up and only two of them are arrivals: somebody
/// else's message landing at the live tail, and your own going up the moment
/// you press enter. Opening a chat, paging history in from above, and the
/// server acking a message already on screen are not — and each of those is a
/// whole screen of rows at once, which is what makes getting it wrong loud.
void main() {
  setUpAll(() => HydratedBloc.storage = _MemoryStorage());

  final base = DateTime.utc(2026, 1, 1, 12);

  ChatMessage msg(String id, {bool mine = false, bool pending = false}) =>
      ChatMessage(
        id: id,
        authorId: mine ? 'me' : 'them',
        authorName: mine ? 'Me' : 'Ana',
        text: 'hi',
        sentAt: base.add(Duration(seconds: int.tryParse(id) ?? 99)),
        isMine: mine,
        isPending: pending,
      );

  Future<void> pump(WidgetTester tester, List<ChatMessage> messages) {
    return tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<ThemeCubit>(create: (_) => ThemeCubit()),
          // The row's message cover reads the sensitive-content setting.
          BlocProvider<AppCubit>(create: (_) => AppCubit()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ChatMessageList(
              // Keyed, so a re-pump updates this list rather than building a
              // fresh one — which would prime again and hide everything these
              // are about.
              key: const ValueKey('list'),
              messages: messages,
            ),
          ),
        ),
      ),
    );
  }

  /// Whether the row for [rowId] is actually mid-entrance — not merely whether
  /// it was told it was new, which the list stops saying almost immediately.
  bool entering(WidgetTester tester, String rowId) => find
      .descendant(
        of: find.byKey(ValueKey(rowId)),
        matching: find.byType(TweenAnimationBuilder<double>),
      )
      .evaluate()
      .isNotEmpty;

  testWidgets('opening a chat does not animate the backlog', (tester) async {
    await pump(tester, [msg('1'), msg('2'), msg('3')]);

    for (final id in ['1', '2', '3']) {
      expect(entering(tester, id), isFalse, reason: id);
    }
  });

  testWidgets('a message from somebody else animates in', (tester) async {
    await pump(tester, [msg('1')]);
    await pump(tester, [msg('1'), msg('2')]);

    expect(entering(tester, '2'), isTrue);
    expect(entering(tester, '1'), isFalse);
  });

  testWidgets('your own message animates the moment you send it', (
    tester,
  ) async {
    // It goes up optimistically, so there is no wait to cover — but a row
    // still comes out of nothing, and that is the pop.
    await pump(tester, [msg('1')]);
    await pump(tester, [msg('1'), msg('pending-0', mine: true, pending: true)]);

    expect(entering(tester, 'pending-0'), isTrue);
  });

  testWidgets('the server acking it does not cut the entrance short', (
    tester,
  ) async {
    // The case a fast server hits: the ack lands inside the 220ms, the row is
    // handed a real id, and keying by that id would throw the row away and
    // build a new one that has already finished arriving.
    await pump(tester, [msg('1')]);
    final sent = [msg('1'), msg('pending-0', mine: true, pending: true)];
    await pump(tester, sent);
    await tester.pump(const Duration(milliseconds: 40));

    final acked = ChatMessageOps.replacePending(
      sent,
      pendingId: 'pending-0',
      acked: msg('2', mine: true),
    );
    await pump(tester, acked);

    expect(
      entering(tester, 'pending-0'),
      isTrue,
      reason: 'the row survives the ack, still under the id it was drawn with',
    );
    expect(find.byType(ChatMessageRow), findsNWidgets(2));
  });

  testWidgets('the ack is not itself a second arrival', (tester) async {
    // Long after the entrance is over: the acked copy must not animate on its
    // own account, or every message you send would arrive twice.
    await pump(tester, [msg('1')]);
    final sent = [msg('1'), msg('pending-0', mine: true, pending: true)];
    await pump(tester, sent);
    // Fixed frames rather than pumpAndSettle: a pending row carries a spinner
    // that never settles, and waiting for it to would be waiting forever.
    for (var frame = 0; frame < 8; frame++) {
      await tester.pump(const Duration(milliseconds: 40));
    }

    await pump(
      tester,
      ChatMessageOps.replacePending(
        sent,
        pendingId: 'pending-0',
        acked: msg('2', mine: true),
      ),
    );
    await tester.pump();

    // What matters is that no *new* row appeared claiming to be arriving.
    expect(find.byType(ChatMessageRow), findsNWidgets(2));
    expect(entering(tester, '2'), isFalse, reason: 'not keyed by the new id');
  });

  testWidgets('paging history in from above animates nothing', (tester) async {
    // Older ids, arriving all at once, below the high-water mark. Without the
    // tail check this is a screenful of rows all sliding at once every time
    // you scroll up.
    await pump(tester, [msg('50'), msg('51')]);
    await pump(tester, [msg('47'), msg('48'), msg('49'), msg('50'), msg('51')]);

    for (final id in ['47', '48', '49']) {
      expect(entering(tester, id), isFalse, reason: id);
    }
  });
}
