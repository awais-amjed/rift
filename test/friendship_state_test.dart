import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/enums/friendship_state.dart';

/// The five answers `friendship_state()` gives, and the three questions the UI
/// asks of them. Both sides spell the values the same way on purpose, so a
/// rename on either end has to break something here.
void main() {
  group('parsing', () {
    test('round-trips every value', () {
      for (final state in FriendshipState.values) {
        expect(FriendshipState.parse(state.toJson()), state);
      }
    });

    test('anything unrecognised reads as none', () {
      // The state with the fewest assumptions in it: a client that has not
      // heard of a newer value should treat the person as a stranger, not
      // silently grant them a friend's composer.
      expect(FriendshipState.parse('acquaintance'), FriendshipState.none);
      expect(FriendshipState.parse(null), FriendshipState.none);
      expect(FriendshipState.parse(7), FriendshipState.none);
      expect(FriendshipState.parse(''), FriendshipState.none);
    });
  });

  group('what each state allows', () {
    test('the composer belongs to friends and to nobody else', () {
      // The whole gate, in one property. A stranger used to be allowed one
      // message — the message *was* the request — and that turned out to be a
      // channel: withdraw, re-ask, send another, forever. Nothing may be sent
      // now until the request is accepted, so `friends` is the only value that
      // can open a composer, and every other one has a note where the field
      // would be.
      expect(FriendshipState.friends.canSend, isTrue);
      expect(FriendshipState.none.canSend, isFalse);
      expect(FriendshipState.outgoing.canSend, isFalse);
      expect(FriendshipState.incoming.canSend, isFalse);
      expect(FriendshipState.blocked.canSend, isFalse);
    });

    test('exactly one state opens a composer', () {
      // Written as a count rather than five expectations, so that adding a
      // state to the enum fails here rather than quietly getting a composer.
      expect(
        FriendshipState.values.where((s) => s.canSend).toList(),
        [FriendshipState.friends],
      );
    });

    test('only an incoming request is waiting on you', () {
      expect(FriendshipState.incoming.isRequest, isTrue);
      expect(FriendshipState.outgoing.isRequest, isFalse);
      expect(FriendshipState.friends.isRequest, isFalse);
    });
  });
}
