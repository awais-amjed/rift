import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/classes/chat_message.dart';
import 'package:rift/data/enums/message_origin.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/chat/chat_message_list.dart';
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

/// A webhook's message is not a member's, and the list has to keep saying so.
///
/// The whole webhook design rests on one visible fact: this message was not
/// encrypted, and no person sent it. Everything here is about that fact
/// surviving contact with the rendering rules — most of all the grouping rule,
/// which hides the header of a message that follows one from the same speaker,
/// and would happily hide the badge along with it.
void main() {
  setUpAll(() => HydratedBloc.storage = _MemoryStorage());

  final base = DateTime.utc(2026, 1, 1, 12);

  ChatMessage member(String id, {String who = 'ana'}) => ChatMessage(
    id: id,
    authorId: who,
    authorName: who,
    text: 'hello',
    sentAt: base.add(Duration(seconds: int.parse(id))),
    isMine: false,
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

  Future<void> pump(WidgetTester tester, List<ChatMessage> messages) {
    return tester.pumpWidget(
      BlocProvider<ThemeCubit>(
        create: (_) => ThemeCubit(),
        child: MaterialApp(
          home: Scaffold(body: ChatMessageList(messages: messages)),
        ),
      ),
    );
  }

  group('the badge', () {
    test('a member\'s sealed message does not get one', () {
      expect(MessageOriginBadge.isNeededFor(member('1')), isFalse);
    });

    test('a webhook message does', () {
      expect(MessageOriginBadge.isNeededFor(hook('1')), isTrue);
    });

    test('so does a member message that was not encrypted', () {
      // Nothing produces this yet — bot commands will (BOTS.md §4). The badge
      // answers to `isEncrypted`, not to who sent it, and that has to hold
      // before the thing that relies on it exists.
      final plainMember = ChatMessage(
        id: '1',
        authorId: 'ana',
        authorName: 'ana',
        text: '/play something',
        sentAt: base,
        isMine: true,
        isEncrypted: false,
      );
      expect(MessageOriginBadge.isNeededFor(plainMember), isTrue);
    });

    testWidgets('it is drawn on the row', (tester) async {
      await pump(tester, [hook('1')]);
      expect(find.byType(MessageOriginBadge), findsOneWidget);
    });

    testWidgets('and not on an ordinary one', (tester) async {
      await pump(tester, [member('1')]);
      expect(find.byType(MessageOriginBadge), findsNothing);
    });
  });

  group('grouping', () {
    test('two webhooks with different names are different speakers', () {
      // Both carry an empty authorId, which is what the grouping key used to
      // be — so this is the case that silently drew the second under the
      // first one's name, with no header and therefore no badge.
      expect(
        hook('1', name: 'GitHub').groupKey,
        isNot(hook('2', name: 'Sentry').groupKey),
      );
    });

    test('the same webhook twice in a row is one speaker', () {
      expect(hook('1').groupKey, hook('2').groupKey);
    });

    test('a webhook never groups with a member of the same name', () {
      expect(hook('1', name: 'ana').groupKey, isNot(member('2').groupKey));
    });

    test('encrypted and plaintext from one member are different speakers', () {
      final sealed = member('1');
      final plain = ChatMessage(
        id: '2',
        authorId: 'ana',
        authorName: 'ana',
        text: '/play',
        sentAt: base,
        isMine: false,
        isEncrypted: false,
      );
      expect(sealed.groupKey, isNot(plain.groupKey));
    });

    testWidgets('two different webhooks each keep their header', (
      tester,
    ) async {
      await pump(tester, [
        hook('1', name: 'GitHub'),
        hook('2', name: 'Sentry'),
      ]);

      // A header each means a name each — and a badge each.
      expect(find.byType(MessageRowHeader), findsNWidgets(2));
      expect(find.byType(MessageOriginBadge), findsNWidgets(2));
      expect(find.text('Sentry'), findsOneWidget);
    });

    testWidgets('the same webhook posting twice still groups', (tester) async {
      await pump(tester, [hook('1'), hook('2')]);
      expect(find.byType(MessageRowHeader), findsOneWidget);
    });
  });

  group('attribution', () {
    test('a webhook message carries no author id', () {
      // Nothing may resolve it to a profile, open a DM with it, or treat it as
      // a member. The empty string is what makes that impossible rather than
      // merely unlikely.
      expect(hook('1').authorId, isEmpty);
    });

    test('and is never mine', () {
      expect(hook('1').isMine, isFalse);
    });

    test('copyWith keeps the origin', () {
      // Reactions and edits both go through copyWith, and a webhook message
      // that quietly became a member's on its first reaction would lose the
      // badge for good.
      final copied = hook('1').copyWith(text: 'edited');
      expect(copied.origin, MessageOrigin.webhook);
      expect(copied.isEncrypted, isFalse);
    });
  });

  group('reading a row', () {
    test('origin comes from the name, not the id', () {
      // `webhook_id` is nulled when the webhook is revoked while the message
      // stays. Keying off it would turn every message a removed integration
      // posted back into a member's, under no name at all.
      expect(
        MessageOrigin.fromRow({'webhook_id': null, 'origin_name': 'GitHub'}),
        MessageOrigin.webhook,
      );
    });

    test('a member row has neither', () {
      expect(
        MessageOrigin.fromRow({'webhook_id': null, 'origin_name': null}),
        MessageOrigin.member,
      );
    });
  });
}
