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

  group('ParticipantIdentity sound shares', () {
    const sound = '$userId~$device${ParticipantIdentity.soundShareSuffix}';
    const screen = '$userId~$device${ParticipantIdentity.screenshareSuffix}';

    test('a sound share is a share, mapped to the connection that made it', () {
      expect(ParticipantIdentity.isSoundShare(sound), isTrue);
      expect(ParticipantIdentity.isScreenshare(sound), isFalse);
      expect(ParticipantIdentity.isShare(sound), isTrue);
      expect(ParticipantIdentity.baseOf(sound), '$userId~$device');
      expect(ParticipantIdentity.userIdOf(sound), userId);
    });

    // Turning the music down must not turn its owner down, so the two
    // settings cannot share a key.
    test('its settings key is not the owner’s', () {
      expect(
        ParticipantIdentity.soundShareSettingsKey(sound),
        isNot(ParticipantIdentity.userIdOf(sound)),
      );
      // And it survives a restart, where the device segment does not.
      expect(
        ParticipantIdentity.soundShareSettingsKey(
          '$userId~zzzzzzzz${ParticipantIdentity.soundShareSuffix}',
        ),
        ParticipantIdentity.soundShareSettingsKey(sound),
      );
    });

    // Four things of one person's are heard separately — voice, screen
    // share, sound share, soundboard — and each is turned down on its own.
    test('each kind of audio has its own settings key', () {
      final keys = {
        ParticipantIdentity.settingsKeyOf('$userId~$device'),
        ParticipantIdentity.settingsKeyOf(screen),
        ParticipantIdentity.settingsKeyOf(sound),
        ParticipantIdentity.soundboardSettingsKey(userId),
      };
      expect(keys, hasLength(4));
      expect(ParticipantIdentity.settingsKeyOf('$userId~$device'), userId);
    });

    // Streaming again is a new connection with a new device segment; the
    // volume set last time has to find it.
    test('a restarted screen share finds the same key', () {
      expect(
        ParticipantIdentity.settingsKeyOf(
          '$userId~zzzzzzzz${ParticipantIdentity.screenshareSuffix}',
        ),
        ParticipantIdentity.settingsKeyOf(screen),
      );
    });

    // A phone streams on the connection it talks on; the track, not the
    // identity, says the sound is a stream's.
    test('screen audio on a voice connection is filed as the stream', () {
      expect(
        ParticipantIdentity.settingsKeyOf('$userId~$device', screenAudio: true),
        ParticipantIdentity.settingsKeyOf(screen),
      );
    });

    // A sound share's track is published as screen audio too; filing it by
    // the source put its saved volume where nothing would read it.
    test('a sound share stays a sound share whatever its track says', () {
      expect(
        ParticipantIdentity.settingsKeyOf(sound, screenAudio: true),
        ParticipantIdentity.soundShareSettingsKey(sound),
      );
    });

    // Your own share reaches you as a remote connection. Missing this is the
    // sharer hearing their own music back, a beat late.
    group('isShareOf', () {
      test('recognises this device’s own shares', () {
        expect(ParticipantIdentity.isShareOf(sound, '$userId~$device'), isTrue);
        expect(
          ParticipantIdentity.isShareOf(screen, '$userId~$device'),
          isTrue,
        );
      });

      // The same person on a phone is not playing the music out loud, so
      // they should hear the share like anybody else.
      test('a share from another device of theirs is not this one’s', () {
        expect(
          ParticipantIdentity.isShareOf(sound, '$userId~otherdev'),
          isFalse,
        );
      });

      test('the connection itself is not one of its own shares', () {
        expect(
          ParticipantIdentity.isShareOf('$userId~$device', '$userId~$device'),
          isFalse,
        );
      });
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

    // A shared track is somebody's music, not their voice. Muting the person
    // must not silence it, and muting it must not silence the person.
    test('leaves their shared sound out', () {
      const sound = '$userId~$device${ParticipantIdentity.soundShareSuffix}';
      expect(ParticipantIdentity.isVoiceConnectionOf(sound, userId), isFalse);
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
