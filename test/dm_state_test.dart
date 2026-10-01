import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/dm_conversation.dart';
import 'package:rift/logic/cubits/dm/dm_cubit.dart';

/// "Couldn't load" and "none yet" are different things to say about an empty
/// Server DMs list — and the flag is also what makes the next reconnect read
/// it again, so it must survive every unrelated change to the state.
void main() {
  test('a fresh state has not failed', () {
    expect(const DmState().conversationsFailed, isFalse);
  });

  test('a failed read survives unrelated changes, and clears on a good one', () {
    final failed = const DmState().copyWith(
      conversationsLoading: false,
      conversationsFailed: true,
    );
    // A conversation opening, typing, a request arriving — none of them say
    // anything about whether the list loaded.
    final later = failed
        .copyWith(openPeerId: 'p1', openPeerName: 'Tester B')
        .copyWith(typingPeerName: 'Tester B')
        .copyWith(requests: const [DmConversation(peerId: 'p2', peerName: 'x')])
        .copyWith(closeConversation: true);
    expect(later.conversationsFailed, isTrue);

    final loaded = later.copyWith(
      conversations: const [DmConversation(peerId: 'p1', peerName: 'Tester B')],
      conversationsFailed: false,
    );
    expect(loaded.conversationsFailed, isFalse);
  });
}
