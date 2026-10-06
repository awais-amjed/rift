import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/classes/chat_message.dart';
import 'package:rift/logic/cubits/app/app_cubit.dart';
import 'package:rift/logic/cubits/server_members/server_members_cubit.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/chat/message_row/chat_message_row.dart';

import 'support/stub_members_cubit.dart';

/// In-memory stand-in so [ThemeCubit] (a HydratedCubit) can be built in tests.
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

/// Every action a message has — react, copy, edit, delete — used to be behind
/// a hover toolbar or a right-click. A finger does neither, so on a phone a
/// message could not be acted on at all: no edit, no delete, no copy, and the
/// reaction picker unreachable even though reactions rendered fine.
///
/// Long press is the touch equivalent of the right-click that was already
/// there, so this is really one guard: that the second gesture reaches the
/// same menu, and that the menu carries the toolbar-only action too.
void main() {
  setUpAll(() => HydratedBloc.storage = _MemoryStorage());

  ChatMessage message({bool mine = true, bool pending = false}) => ChatMessage(
    id: 'm1',
    authorId: mine ? 'me' : 'them',
    authorName: mine ? 'Me' : 'Them',
    text: 'hello there',
    sentAt: DateTime.utc(2026, 1, 1),
    isMine: mine,
    isPending: pending,
  );

  /// [settle] is off for a message still sending: it renders a spinner that
  /// never stops, so `pumpAndSettle` waits for a frame that never comes.
  Future<void> pumpRow(
    WidgetTester tester, {
    required ChatMessage msg,
    bool withCallbacks = true,
    bool settle = true,
    double windowWidth = 390,
  }) async {
    await tester.pumpWidget(
      MediaQuery(
        // The width is what makes the row plain rather than selectable,
        // which is what lets the long press through to the row. Defaults to a
        // phone, which is what these are about.
        data: MediaQueryData(size: Size(windowWidth, 800)),
        child: MaterialApp(
          home: MultiBlocProvider(
            providers: [
              BlocProvider<ThemeCubit>(create: (_) => ThemeCubit()),
              // The row's message cover reads the sensitive-content setting.
              BlocProvider<AppCubit>(create: (_) => AppCubit()),
              BlocProvider<ServerMembersCubit>(
                create: (_) => StubMembersCubit(),
              ),
            ],
            child: BlocBuilder<ThemeCubit, ThemeState>(
              builder: (context, themeState) => Scaffold(
                body: ChatMessageRow(
                  message: msg,
                  showHeader: true,

                  onToggleReaction: withCallbacks ? (_, _) {} : null,
                  onEdit: withCallbacks ? (_, _) {} : null,
                  onDelete: withCallbacks ? (_) {} : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  testWidgets('a long press opens the message menu', (tester) async {
    await pumpRow(tester, msg: message());
    await tester.longPress(find.text('hello there'));
    await tester.pumpAndSettle();

    expect(find.text('Copy text'), findsOneWidget);
    expect(find.text('Edit message'), findsOneWidget);
    expect(find.text('Delete message'), findsOneWidget);
  });

  testWidgets('the menu carries React, which only the hover toolbar had', (
    tester,
  ) async {
    await pumpRow(tester, msg: message());
    await tester.longPress(find.text('hello there'));
    await tester.pumpAndSettle();

    expect(find.text('Add reaction'), findsOneWidget);
  });

  testWidgets('someone else\'s message offers only what it should', (
    tester,
  ) async {
    await pumpRow(tester, msg: message(mine: false));
    await tester.longPress(find.text('hello there'));
    await tester.pumpAndSettle();

    // Still copyable and still reactable; not editable by someone who did not
    // write it. A menu that offered it would be offering a refusal.
    expect(find.text('Copy text'), findsOneWidget);
    expect(find.text('Add reaction'), findsOneWidget);
    expect(find.text('Edit message'), findsNothing);
  });

  testWidgets('a desktop keeps its selectable text', (tester) async {
    // The reason the long press gets through on a phone is that the row is
    // no longer a selection region, whose own long-press recognizer wins the
    // arena. That trade is only worth making where there is no mouse: with a
    // cursor, dragging across a message to copy part of it is a normal thing
    // to do and there is a right-click for the menu.
    await pumpRow(tester, msg: message(), windowWidth: 1400);
    expect(find.byType(SelectionArea), findsOneWidget);
  });

  testWidgets('a phone trades selection for the menu', (tester) async {
    await pumpRow(tester, msg: message());
    expect(find.byType(SelectionArea), findsNothing);
  });

  testWidgets('a message still on its way opens nothing', (tester) async {
    // It has no id on the server yet, so every entry would act on something
    // that does not exist.
    await pumpRow(tester, msg: message(pending: true), settle: false);
    await tester.longPress(find.text('hello there'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Copy text'), findsNothing);
    expect(find.text('Add reaction'), findsNothing);
  });
}
