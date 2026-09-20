import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/attachment.dart';
import 'package:rift/data/classes/channel.dart';
import 'package:rift/data/classes/chat_message.dart';
import 'package:rift/data/classes/dm_conversation.dart';
import 'package:rift/data/classes/forwarded_message.dart';
import 'package:rift/data/classes/message_body.dart';
import 'package:rift/data/classes/server.dart';
import 'package:rift/data/enums/channel_type.dart';
import 'package:rift/logic/services/forwarding/forward_payload.dart';
import 'package:rift/logic/services/forwarding/forward_target.dart';
import 'package:rift/logic/services/forwarding/forward_targets.dart';

/// Carrying a message into another conversation. The three things that are
/// easy to get wrong: what a forward is allowed to claim, what it carries
/// when it is forwarded on, and where it may be sent.
void main() {
  Attachment att(String name) => Attachment(
    id: name,
    kind: AttachmentKind.image,
    name: name,
    mime: 'image/png',
    size: 10,
    storagePath: 'src/$name.bin',
    keyB64: 'k',
    nonceB64: 'n',
  );

  ChatMessage msg({
    String text = 'the original',
    String author = 'ana',
    List<Attachment> attachments = const [],
    bool isLocked = false,
    bool isPending = false,
    ForwardedMessage? forwarded,
  }) => ChatMessage(
    id: '1',
    authorId: author,
    authorName: author,
    text: text,
    attachments: attachments,
    isLocked: isLocked,
    isPending: isPending,
    forwarded: forwarded,
    sentAt: DateTime.utc(2026, 9, 20, 12),
    isMine: false,
  );

  Channel channel(String id, String name, {ChannelType? type}) => Channel(
    id: id,
    name: name,
    channelType: type ?? ChannelType.text,
  );

  Server server(String id, String name, List<Channel> channels) => Server(
    id: id,
    name: name,
    supabaseUrl: 'https://$id.example',
    token: 't',
    channels: channels,
    keyVersion: 'v1',
    tokenIssuedAt: DateTime.utc(2026, 9, 20),
  );

  group('ForwardPayload', () {
    test('carries the content, because the reader cannot resolve an id', () {
      // The opposite of a reply. Nobody at the destination holds a key to
      // the room this came from, so there is nothing there to point at.
      final payload = ForwardPayload.of(
        msg(attachments: [att('a')]),
        source: '#general in Proxy Test',
      )!;
      expect(payload.authorName, 'ana');
      expect(payload.text, 'the original');
      expect(payload.attachments.single.name, 'a');
      expect(payload.source, '#general in Proxy Test');
    });

    test('forwarding a forward flattens to the first author', () {
      // Wrapping again would attribute the words to whoever passed them to
      // you, which is the claim going wrong as the message travels.
      final inner = ForwardedMessage(
        authorName: 'ana',
        sentAt: DateTime.utc(2026, 9, 1),
        text: 'said first',
      );
      final payload = ForwardPayload.of(
        msg(text: 'look at this', author: 'bo', forwarded: inner),
        source: 'somewhere else',
      )!;
      expect(payload.authorName, 'ana');
      expect(payload.text, 'said first');
      // The middle person's own line is not swallowed into the quote.
      expect(payload.text, isNot(contains('look at this')));
    });

    test('a locked message cannot be forwarded', () {
      // Its text is empty because the key never arrived, so the forward
      // would be an empty quote under somebody's name.
      expect(ForwardPayload.of(msg(text: '', isLocked: true)), isNull);
      expect(ForwardPayload.canForward(msg(text: '', isLocked: true)), isFalse);
    });

    test('an empty message cannot be forwarded, a pending one cannot yet', () {
      expect(ForwardPayload.of(msg(text: '')), isNull);
      expect(ForwardPayload.canForward(msg(isPending: true)), isFalse);
      expect(ForwardPayload.canForward(msg()), isTrue);
    });

    test('a very long message is cut rather than refused', () {
      final payload = ForwardPayload.of(msg(text: 'x' * 9000))!;
      expect(payload.text.length, ForwardedMessage.maxText + 1);
      expect(payload.text, endsWith('…'));
    });
  });

  group('ForwardedMessage on the wire', () {
    test('round-trips inside the sealed body', () {
      final body = MessageBody(
        text: 'worth reading',
        forwarded: ForwardedMessage(
          authorName: 'ana',
          sentAt: DateTime.utc(2026, 9, 1, 8, 30),
          text: 'hello',
          attachments: [att('a')],
          source: '#general',
        ),
      );
      final back = MessageBody.decode(body.encode()).forwarded!;
      expect(back.authorName, 'ana');
      expect(back.sentAt, DateTime.utc(2026, 9, 1, 8, 30));
      expect(back.text, 'hello');
      expect(back.attachments.single.storagePath, 'src/a.bin');
      expect(back.source, '#general');
    });

    test('a forward with no words of its own is not an empty body', () {
      final body = MessageBody(
        forwarded: ForwardedMessage(
          authorName: 'ana',
          sentAt: DateTime.utc(2026, 9, 1),
          text: 'hi',
        ),
      );
      expect(body.isEmpty, isFalse);
      expect(const MessageBody().isEmpty, isTrue);
    });

    test('a half-built forward is dropped whole', () {
      // It arrived inside somebody else's message. Half of one is a quote
      // with no attribution, which is the one thing this must not draw.
      for (final raw in [
        '{"at":"2026-09-01T00:00:00Z"}',
        '{"by":"","at":"2026-09-01T00:00:00Z"}',
        '{"by":"ana"}',
        '{"by":"ana","at":"not a date"}',
        '"ana"',
        '[]',
      ]) {
        final body = MessageBody.decode(
          '{"t":"rift.msg","v":1,"text":"x","fwd":$raw}',
        );
        expect(body.forwarded, isNull, reason: raw);
        expect(body.text, 'x', reason: raw);
      }
    });

    test('an unreadable attachment costs only itself', () {
      final back = ForwardedMessage.fromJson({
        'by': 'ana',
        'at': '2026-09-01T00:00:00Z',
        'text': 'two files',
        'att': [
          {'id': 'bad'},
          att('good').toJson(),
        ],
      })!;
      expect(back.attachments.single.name, 'good');
      expect(back.text, 'two files');
    });

    test('the text cap is enforced on the way in, not just out', () {
      // The sender is not the one applying this client's limits.
      final back = ForwardedMessage.fromJson({
        'by': 'ana',
        'at': '2026-09-01T00:00:00Z',
        'text': 'y' * 20000,
      })!;
      expect(back.text.length, ForwardedMessage.maxText);
    });

    test('withAttachments swaps the copies and keeps the claim', () {
      final original = ForwardedMessage(
        authorName: 'ana',
        sentAt: DateTime.utc(2026, 9, 1),
        text: 'hi',
        attachments: [att('src')],
        source: '#general',
      );
      final copied = original.withAttachments([att('dest')]);
      expect(copied.attachments.single.name, 'dest');
      expect(copied.authorName, 'ana');
      expect(copied.source, '#general');
    });
  });

  group('ForwardTargets', () {
    final home = server('s1', 'Proxy Test', [
      channel('c1', 'general'),
      channel('c2', 'random'),
      channel('v1', 'voice', type: ChannelType.voice),
    ]);
    final other = server('s2', 'Elsewhere', [channel('c3', 'lobby')]);

    DmConversation peer(String id, String name) =>
        DmConversation(peerId: id, peerName: name, peerChatPublicKey: 'k');

    test('gathers text channels across every server', () {
      final targets = ForwardTargets.gather(servers: [home, other]);
      expect(targets.map((t) => t.label), ['#general', '#random', '#lobby']);
    });

    test('a voice channel has no message list to forward into', () {
      final targets = ForwardTargets.gather(servers: [home]);
      expect(targets.map((t) => t.label), isNot(contains('#voice')));
    });

    test('leaves out where the message already is', () {
      // "Forward this to here" is never the intent, and offering it is how
      // a mis-click duplicates a message in place.
      final targets = ForwardTargets.gather(
        servers: [home],
        currentChannelId: 'c1',
      );
      expect(targets.map((t) => t.label), ['#random']);
    });

    test('DMs come with the key their message will be sealed under', () {
      final targets = ForwardTargets.gather(
        servers: const [],
        serverDms: [peer('u1', 'Bo')],
        serverDmHost: home,
        centralDms: [peer('u2', 'cara')],
      );
      expect(targets.length, 2);
      expect((targets[0] as ServerDmTarget).peerChatPublicKey, 'k');
      expect((targets[1] as CentralDmTarget).peerHandle, 'cara');
      expect(targets[1].label, '@cara');
    });

    test('server DMs need a host to be sent through', () {
      // Without one there is no url to post to and no identity to sign with.
      final targets = ForwardTargets.gather(
        servers: const [],
        serverDms: [peer('u1', 'Bo')],
      );
      expect(targets, isEmpty);
    });

    test('the open conversation is left out of both DM lists', () {
      final targets = ForwardTargets.gather(
        servers: const [],
        serverDms: [peer('u1', 'Bo')],
        serverDmHost: home,
        centralDms: [peer('u1', 'Bo')],
        currentPeerId: 'u1',
      );
      expect(targets, isEmpty);
    });

    test('every target has a stable, distinct id', () {
      final targets = ForwardTargets.gather(
        servers: [home, other],
        serverDms: [peer('u1', 'Bo')],
        serverDmHost: home,
        centralDms: [peer('u1', 'Bo')],
      );
      final ids = targets.map((t) => t.id).toSet();
      expect(ids.length, targets.length);
      // The same person on two tiers is two destinations, not one.
      expect(ids, contains('dm:s1:u1'));
      expect(ids, contains('central:u1'));
    });
  });

  group('ForwardTargetSearch', () {
    final home = server('s1', 'Proxy Test', [
      channel('c1', 'general'),
      channel('c2', 'gardening'),
      channel('c3', 'random'),
    ]);
    final targets = ForwardTargets.gather(
      servers: [home],
      centralDms: [
        DmConversation(peerId: 'u1', peerName: 'gene', peerChatPublicKey: 'k'),
      ],
    );

    test('matches without the sigil, since nobody types it', () {
      final hit = ForwardTargetSearch.filter(targets, 'gen');
      expect(hit.map((t) => t.label), ['#general', '@gene']);
    });

    test('a prefix outranks a match in the middle', () {
      final hit = ForwardTargetSearch.filter(targets, 'and');
      expect(hit.first.label, '#random');
    });

    test('the server name finds its channels', () {
      expect(ForwardTargetSearch.filter(targets, 'proxy').length, 3);
    });

    test('an empty query is everything, in order', () {
      expect(ForwardTargetSearch.filter(targets, '  '), targets);
    });
  });
}
