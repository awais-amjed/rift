import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/cubits/channel_presence/channel_presence_cubit.dart';

void main() {
  group('ChannelPresenceState.isElsewhere', () {
    const state = ChannelPresenceState(
      channelPresence: {
        'general': [PresenceUser(userId: 'u1', displayName: 'Ada')],
        'gaming': [PresenceUser(userId: 'u2', displayName: 'Bo')],
      },
      onlineUserIds: {'u1', 'u2', 'u3'},
    );

    test('true when their broadcast names a different channel', () {
      // The move case: LiveKit still lists u2 in general, but u2 has already
      // said they're in gaming, so general must stop drawing them.
      expect(state.isElsewhere('u2', 'general'), isTrue);
    });

    test('false when their broadcast names this channel', () {
      expect(state.isElsewhere('u1', 'general'), isFalse);
    });

    test('false when we have no location for them at all', () {
      // Online but never heard announcing, or the snapshot missed them —
      // LiveKit is the only thing that knows, so it keeps them.
      expect(state.isElsewhere('u3', 'general'), isFalse);
      expect(state.isElsewhere('nobody', 'general'), isFalse);
    });

    test('false for the local user, who is never in the rosters', () {
      // channelOf deliberately never answers for us, so this can never hide
      // us from the call we're in.
      expect(state.isElsewhere('me', 'general'), isFalse);
    });
  });
}
