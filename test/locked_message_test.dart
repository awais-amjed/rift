import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rift/logic/cubits/app/app_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/classes/chat_message.dart';
import 'package:rift/data/enums/message_origin.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/logic/services/message_permissions.dart';
import 'package:rift/presentation/common/chat/chat_message_list.dart';
import 'package:rift/presentation/common/chat/message_row/message_locked_body.dart';
import 'package:rift/presentation/common/chat/message_row/message_origin_badge.dart';
import 'package:rift/presentation/common/chat/message_row/message_row_header.dart';

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

/// A message you cannot open is not a message that is not there.
///
/// Before this, a channel whose key had not been wrapped for you yet looked
/// empty — every row was dropped by the same line that drops a forged message.
/// These cover the two halves of the fix: locked rows are rendered, and the
/// thing that must still be dropped still is.
void main() {
  setUpAll(() => HydratedBloc.storage = _MemoryStorage());

  final base = DateTime.utc(2026, 1, 1, 12);

  ChatMessage readable(String id, {String who = 'ana'}) => ChatMessage(
    id: id,
    authorId: who,
    authorName: who,
    text: 'hello',
    sentAt: base.add(Duration(seconds: int.parse(id))),
    isMine: false,
  );

  ChatMessage locked(String id, {String who = 'ana', bool mine = false}) =>
      ChatMessage(
        id: id,
        authorId: who,
        authorName: who,
        text: '',
        sentAt: base.add(Duration(seconds: int.parse(id))),
        isMine: mine,
        isLocked: true,
      );

  ChatMessage hook(String id, {String name = 'GitHub'}) => ChatMessage(
    id: id,
    authorId: '',
    authorName: name,
    text: 'build passed',
    sentAt: base.add(Duration(seconds: int.parse(id))),
    isMine: false,
    origin: MessageOrigin.webhook,
    isEncrypted: false,
  );

  Future<void> pump(
    WidgetTester tester,
    List<ChatMessage> messages, {
    bool moderator = false,
  }) {
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
              messages: messages,
              isModerator: moderator,
              onToggleReaction: (_, _) {},
              onDelete: (_) {},
              onEdit: (_, _) {},
            ),
          ),
        ),
      ),
    );
  }

  group('rendering', () {
    testWidgets('a locked message says so instead of disappearing', (
      tester,
    ) async {
      await pump(tester, [locked('1')]);
      expect(find.byType(MessageLockedBody), findsOneWidget);
    });

    testWidgets('it still carries its author and time', (tester) async {
      // Both come from columns the server already stores in the clear, so
      // showing them reveals nothing — and without them the row is a grey
      // smear that says nothing about whose history this is.
      await pump(tester, [locked('1', who: 'ana')]);
      expect(find.text('ana'), findsOneWidget);
      expect(find.byType(MessageRowHeader), findsOneWidget);
    });

    testWidgets('a readable message never gets one', (tester) async {
      await pump(tester, [readable('1')]);
      expect(find.byType(MessageLockedBody), findsNothing);
    });

    testWidgets('locked and readable rows coexist in order', (tester) async {
      // The mixed case is the whole point: a member with no channel key can
      // still read what a webhook posted, and should be able to see that the
      // rest of the room exists.
      await pump(tester, [locked('1'), hook('2'), locked('3')]);
      expect(find.byType(MessageLockedBody), findsNWidgets(2));
      expect(find.text('build passed'), findsOneWidget);
      expect(find.byType(MessageOriginBadge), findsOneWidget);
    });
  });

  group('what you may do to one', () {
    test('never edit — there is no text to edit', () {
      expect(MessagePermissions.canEdit(locked('1', mine: true)), isFalse);
    });

    test('your own is still yours to delete', () {
      // Not being able to read it does not make it somebody else's message.
      expect(
        MessagePermissions.canDelete(
          locked('1', mine: true),
          isModerator: false,
        ),
        isTrue,
      );
    });

    test('a moderator may still remove it', () {
      expect(
        MessagePermissions.canDelete(locked('1'), isModerator: true),
        isTrue,
      );
    });

    testWidgets('no reaction bar — reacting to what you cannot read', (
      tester,
    ) async {
      // Reactions are not encrypted, so a tally on an unreadable message would
      // be visible to everyone who *can* read it. A mis-click with an audience.
      await pump(tester, [locked('1')]);
      await tester.pumpAndSettle();
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.byType(MessageLockedBody)));
      await tester.pump();
      expect(find.byIcon(Icons.add_reaction_outlined), findsNothing);
    });
  });

  group('grouping', () {
    test('locked and readable from one author are the same speaker', () {
      // A key rotation can leave a run of one person's messages half readable.
      // Splitting the header there would imply two people spoke.
      expect(locked('1').groupKey, readable('2').groupKey);
    });

    test('two authors are still two speakers when both are locked', () {
      expect(
        locked('1', who: 'ana').groupKey,
        isNot(locked('2', who: 'bo').groupKey),
      );
    });
  });
}
