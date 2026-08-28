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

  group('a command you just sent', () {
    // Found by sending one in the real app: the badge logic and the parse
    // logic were both right, and the row in between was built with the default
    // `isEncrypted: true`. So the one message whose sender *chose* plaintext
    // was the one that did not say so — until a reload, which is the worst
    // possible timing for that admission.
    ChatMessage sentCommand({required bool pending}) => ChatMessage(
      id: pending ? 'pending-0' : '99',
      authorId: 'me',
      authorName: 'Me',
      text: '/play rick astley',
      sentAt: base,
      isMine: true,
      isPending: pending,
      isEncrypted: false,
    );

    test('is badged while it is still in flight', () {
      expect(
        MessageOriginBadge.isNeededFor(sentCommand(pending: true)),
        isTrue,
      );
    });

    test('and still badged once the server answers', () {
      expect(
        MessageOriginBadge.isNeededFor(sentCommand(pending: false)),
        isTrue,
      );
    });

    test('but it is still mine, and still from a member', () {
      // Unencrypted does not mean unattributed: a command carries the sender's
      // name, unlike a webhook's message.
      final sent = sentCommand(pending: false);
      expect(sent.isMine, isTrue);
      expect(sent.origin, MessageOrigin.member);
      expect(sent.authorId, isNotEmpty);
    });

    testWidgets('the badge is on the row', (tester) async {
      await pump(tester, [sentCommand(pending: false)]);
      expect(find.byType(MessageOriginBadge), findsOneWidget);
    });
  });

  group('a reply only you can see', () {
    ChatMessage private({String who = 'musicbot'}) => ChatMessage(
      id: '50',
      authorId: who,
      authorName: who,
      text: 'Nothing is playing.',
      sentAt: base,
      isMine: false,
      isEncrypted: false,
      isEphemeral: true,
    );

    ChatMessage publicReply({String who = 'musicbot'}) => ChatMessage(
      id: '51',
      authorId: who,
      authorName: who,
      text: 'Now playing: something',
      sentAt: base.add(const Duration(seconds: 1)),
      isMine: false,
      isEncrypted: false,
    );

    test('is badged', () {
      expect(MessageOriginBadge.isNeededFor(private()), isTrue);
    });

    testWidgets('and says who can see it, not just that it is plaintext', (
      tester,
    ) async {
      // A private reply is unencrypted by construction. The surprising half —
      // that nobody else in the channel has this row — is the one worth the
      // pill, because a message that looks like it is in the channel and is
      // not would be the most confusing thing on the screen.
      await pump(tester, [private()]);
      expect(find.text('ONLY YOU'), findsOneWidget);
      expect(find.text('NOT ENCRYPTED'), findsNothing);
    });

    test('does not group with the same bot\'s public reply', () {
      // Grouping them would hide the second header, and with it the badge that
      // is the only thing distinguishing the two.
      expect(private().groupKey, isNot(publicReply().groupKey));
    });

    testWidgets('so both keep their own header', (tester) async {
      await pump(tester, [publicReply(), private()]);
      expect(find.byType(MessageRowHeader), findsNWidgets(2));
      expect(find.text('ONLY YOU'), findsOneWidget);
    });

    test('survives copyWith, like the other flags', () {
      expect(private().copyWith(text: 'edited').isEphemeral, isTrue);
    });

    test('an ordinary message is never one', () {
      expect(member('1').isEphemeral, isFalse);
      expect(hook('1').isEphemeral, isFalse);
    });
  });

  group('a message the server wrote about itself', () {
    // Same shape as a webhook's — an origin instead of a sender, unencrypted —
    // and different in the one way a badge exists to be honest about: nothing
    // outside the server is involved.
    test('is its own origin, not a webhook', () {
      expect(
        MessageOrigin.fromRow({'origin_name': 'Rift', 'is_system': true}),
        MessageOrigin.system,
      );
      expect(
        MessageOrigin.fromRow({'origin_name': 'CI', 'is_system': false}),
        MessageOrigin.webhook,
      );
    });

    test('a row from a server too old to say is a webhook', () {
      // `is_system` arrived in 028. Absent means the row predates it, and every
      // row that predates it is a webhook's — reading absence as "system"
      // would relabel every integration message ever posted.
      expect(
        MessageOrigin.fromRow({'origin_name': 'CI'}),
        MessageOrigin.webhook,
      );
    });

    test('is still not a member, whatever it is', () {
      expect(MessageOrigin.system.isMember, isFalse);
      expect(MessageOrigin.fromRow({'is_system': true}), MessageOrigin.member);
    });
  });
}
