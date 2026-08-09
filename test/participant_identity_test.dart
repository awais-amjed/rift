import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/participant_identity.dart';

void main() {
  const userId = 'd290f1ee-6c54-4b01-90e6-d701748f0851';
  const device = 'a1b2c3d4';

  group('ParticipantIdentity.userIdOf', () {
    test('strips the device segment', () {
      expect(ParticipantIdentity.userIdOf('$userId~$device'), userId);
    });

    test('strips the screenshare suffix too', () {
      expect(
        ParticipantIdentity.userIdOf(
          '$userId~$device'
          '${ParticipantIdentity.screenshareSuffix}',
        ),
        userId,
      );
    });

    // The context menu for a member of *another* voice channel has no LiveKit
    // identity to pass — only a user id. Local mute/volume storage keys off
    // userIdOf, so a bare id must come back unchanged or the setting would be
    // filed under a different key than the one applied when they join.
    test('returns a bare user id unchanged', () {
      expect(ParticipantIdentity.userIdOf(userId), userId);
    });

    test('a bare id and that user’s identity resolve to the same key', () {
      expect(
        ParticipantIdentity.userIdOf(userId),
        ParticipantIdentity.userIdOf('$userId~$device'),
      );
    });
  });

  group('ParticipantIdentity.baseOf / isScreenshare', () {
    test('a screenshare identity is recognised and mapped to its owner', () {
      const share = '$userId~$device${ParticipantIdentity.screenshareSuffix}';
      expect(ParticipantIdentity.isScreenshare(share), isTrue);
      expect(ParticipantIdentity.baseOf(share), '$userId~$device');
    });

    test('a normal identity is not a screenshare and is its own base', () {
      const identity = '$userId~$device';
      expect(ParticipantIdentity.isScreenshare(identity), isFalse);
      expect(ParticipantIdentity.baseOf(identity), identity);
    });
  });

  // Local mute/volume used to find its target with an exact room-key match on
  // the identity it was handed. That silenced one connection: a member on two
  // devices stayed audible on the other, and muting from the members sidebar
  // (which only has a user id) did nothing at all until they rejoined.
  group('ParticipantIdentity.isVoiceConnectionOf', () {
    const otherDevice = 'e5f6a7b8';
    const share = '$userId~$device${ParticipantIdentity.screenshareSuffix}';

    test('matches every device that user has joined from', () {
      expect(
        ParticipantIdentity.isVoiceConnectionOf('$userId~$device', userId),
        isTrue,
      );
      expect(
        ParticipantIdentity.isVoiceConnectionOf('$userId~$otherDevice', userId),
        isTrue,
      );
    });

    test('leaves their screenshare out', () {
      expect(ParticipantIdentity.isVoiceConnectionOf(share, userId), isFalse);
    });

    test('does not match somebody else', () {
      const other = '9f8e7d6c-0000-4000-8000-000000000000';
      expect(
        ParticipantIdentity.isVoiceConnectionOf('$other~$device', userId),
        isFalse,
      );
    });
  });
}
