import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/cubits/channel_presence/channel_presence_cubit.dart';

void main() {
  group('presence healing', () {
    test('re-tracks when our own entry is missing from the sync', () {
      // What the bug looked like from the inside: we believe we published an
      // entry, and the state the server is broadcasting doesn't have one.
      expect(
        ChannelPresenceCubit.shouldRetrack(
          tracked: true,
          localUserId: 'u1',
          onlineUserIds: {'u2', 'u3'},
        ),
        isTrue,
      );
    });

    test('leaves a healthy entry alone', () {
      expect(
        ChannelPresenceCubit.shouldRetrack(
          tracked: true,
          localUserId: 'u1',
          onlineUserIds: {'u1', 'u2'},
        ),
        isFalse,
      );
    });

    test('does not fight a track that was never made', () {
      // Nothing to heal before we've claimed to be tracked — otherwise every
      // sync between subscribing and tracking would queue another attempt.
      expect(
        ChannelPresenceCubit.shouldRetrack(
          tracked: false,
          localUserId: 'u1',
          onlineUserIds: <String>{},
        ),
        isFalse,
      );
    });

    test('does nothing while we have no identity on this server', () {
      expect(
        ChannelPresenceCubit.shouldRetrack(
          tracked: true,
          localUserId: null,
          onlineUserIds: <String>{},
        ),
        isFalse,
      );
    });
  });
}
