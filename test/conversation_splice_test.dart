import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/chat_message.dart';
import 'package:rift/data/classes/dm_conversation.dart';
import 'package:rift/logic/services/conversation_splice.dart';

DmConversation _conversation(String peerId, {String? lastMessageId}) =>
    DmConversation(
      peerId: peerId,
      peerName: peerId,
      lastMessage: lastMessageId == null
          ? null
          : ChatMessage(
              id: lastMessageId,
              authorId: peerId,
              authorName: peerId,
              text: 'hi',
              sentAt: DateTime(2026),
              isMine: false,
            ),
    );

List<String> _peers(List<DmConversation> list) => [
  for (final conversation in list) conversation.peerId,
];

void main() {
  final list = [
    _conversation('alice', lastMessageId: '30'),
    _conversation('bob', lastMessageId: '20'),
    _conversation('carol', lastMessageId: '10'),
  ];

  test('a new message moves its conversation to the top', () {
    final spliced = ConversationSplice.apply(
      list,
      peerId: 'carol',
      updated: _conversation('carol', lastMessageId: '40'),
    );

    expect(_peers(spliced), ['carol', 'alice', 'bob']);
  });

  // An edit is not a new message, so nothing should jump.
  test('an edit leaves the conversation where it was', () {
    final spliced = ConversationSplice.apply(
      list,
      peerId: 'bob',
      updated: _conversation('bob', lastMessageId: '20'),
    );

    expect(_peers(spliced), ['alice', 'bob', 'carol']);
  });

  test('a conversation that is not in the list yet lands by its message', () {
    final spliced = ConversationSplice.apply(
      list,
      peerId: 'dave',
      updated: _conversation('dave', lastMessageId: '25'),
    );

    expect(_peers(spliced), ['alice', 'dave', 'bob', 'carol']);
  });

  test('nothing to put back removes the conversation', () {
    final spliced = ConversationSplice.apply(
      list,
      peerId: 'bob',
      updated: null,
    );

    expect(_peers(spliced), ['alice', 'carol']);
  });

  test('a conversation with nothing readable in it sorts last', () {
    final spliced = ConversationSplice.apply(
      list,
      peerId: 'dave',
      updated: _conversation('dave'),
    );

    expect(_peers(spliced), ['alice', 'bob', 'carol', 'dave']);
  });
}
