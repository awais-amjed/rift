import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/soundboard_sound.dart';
import 'package:rift/data/participant_identity.dart';
import 'package:rift/data/repositories/soundboard_repository.dart';
import 'package:rift/logic/services/soundboard_play.dart';
import 'package:rift/logic/services/soundboard_staging.dart';

void main() {
  Map<String, dynamic> row({Map<String, dynamic> overrides = const {}}) => {
    'id': 's1',
    'name': 'airhorn',
    'emoji': '📯',
    'object_path': 'srv/abc.audio',
    'duration_ms': 1200,
    'bytes': 9000,
    'created_by': 'u1',
    'created_at': '2026-09-20T09:00:00Z',
    ...overrides,
  };

  group('a clip from the server', () {
    test('round-trips', () {
      final sound = SoundboardSound.fromJson(row());
      expect(sound.duration, const Duration(milliseconds: 1200));
      expect(SoundboardSound.fromJson(sound.toJson()).toJson(), sound.toJson());
    });

    test('survives the columns that are allowed to be absent', () {
      // `emoji` is optional and `created_by` goes to null when whoever added
      // the clip leaves — neither is a reason for a picker to fall over.
      final sound = SoundboardSound.fromJson(
        row(overrides: {'emoji': null, 'created_by': null}),
      );
      expect(sound.emoji, isNull);
      expect(sound.createdBy, isNull);
      expect(sound.name, 'airhorn');
    });

    test('clearing the emoji is distinct from leaving it alone', () {
      final sound = SoundboardSound.fromJson(row());
      expect(sound.copyWith(name: 'horn').emoji, '📯');
      expect(sound.copyWith(clearEmoji: true).emoji, isNull);
    });

    test('the path is not something copyWith can change', () {
      // Deliberate: the server has no UPDATE grant on `object_path`, and
      // every client caches bytes under it forever on the strength of that.
      final sound = SoundboardSound.fromJson(row());
      expect(sound.copyWith(name: 'other').objectPath, 'srv/abc.audio');
    });
  });

  group('what may become a clip', () {
    test('an ordinary small mp3 is fine', () {
      expect(
        SoundboardStaging.rejectionFor(
          fileName: 'horn.mp3',
          mime: 'audio/mpeg',
          bytes: 40000,
        ),
        isNull,
      );
    });

    test('something that is not audio is refused by name', () {
      expect(
        SoundboardStaging.rejectionFor(
          fileName: 'cat.png',
          mime: 'image/png',
          bytes: 1000,
        ),
        contains('cat.png'),
      );
    });

    test('a format only some platforms decode is refused too', () {
      // flac plays on desktop and not on every phone, and a clip that is
      // silence for half the room is worse than one that was refused.
      expect(
        SoundboardStaging.rejectionFor(
          fileName: 'horn.flac',
          mime: 'audio/flac',
          bytes: 1000,
        ),
        isNotNull,
      );
    });

    test('over the size limit is refused before anything is uploaded', () {
      // Relative to the cap, not a number of its own: the cap has moved
      // once already and this test quietly stopped testing anything.
      expect(
        SoundboardStaging.rejectionFor(
          fileName: 'long.mp3',
          mime: 'audio/mpeg',
          bytes: SoundboardRepository.maxBytes + 1,
        ),
        isNotNull,
      );
      expect(
        SoundboardStaging.rejectionFor(
          fileName: 'fine.mp3',
          mime: 'audio/mpeg',
          bytes: SoundboardRepository.maxBytes,
        ),
        isNull,
      );
    });

    test('a name has to be there and has to fit the column', () {
      expect(SoundboardStaging.rejectionForName('  '), isNotNull);
      expect(SoundboardStaging.rejectionForName('a' * 33), isNotNull);
      expect(SoundboardStaging.rejectionForName('airhorn'), isNull);
    });

    test('an unmeasurable length reads as a dash, not as zero seconds', () {
      expect(SoundboardStaging.durationLabel(Duration.zero), '—');
      expect(
        SoundboardStaging.durationLabel(const Duration(milliseconds: 1240)),
        '1.2 s',
      );
      // A whole number keeps no decimal: the cap this labels is 30 seconds,
      // and "30.0 s" reads as a measurement rather than as the rule it is.
      expect(
        SoundboardStaging.durationLabel(const Duration(seconds: 30)),
        '30 s',
      );
    });

    test('a clip past the ceiling is refused, with its real length', () {
      // A refusal and not a warning: "the first 30 seconds of this will
      // play" is almost never what somebody meant by a four-minute track.
      final rejection = SoundboardStaging.rejectionForDuration(
        fileName: 'long-outro.mp3',
        duration: const Duration(seconds: 72, milliseconds: 400),
      );
      expect(rejection, contains('72.4 s'));
      expect(rejection, contains('30 s'));
    });

    test('one inside it passes, including one exactly at it', () {
      expect(
        SoundboardStaging.rejectionForDuration(
          fileName: 'airhorn.mp3',
          duration: const Duration(seconds: 2),
        ),
        isNull,
      );
      expect(
        SoundboardStaging.rejectionForDuration(
          fileName: 'airhorn.mp3',
          duration: SoundboardPlay.maxPlayback,
        ),
        isNull,
      );
    });

    test('and an unmeasurable one passes rather than being guessed at', () {
      // Zero means no backend would answer, not that the file is empty.
      // Refusing on that would make a clip's acceptance depend on which
      // platform added it; maxPlayback is what catches it, at play time.
      expect(
        SoundboardStaging.rejectionForDuration(
          fileName: 'airhorn.wav',
          duration: Duration.zero,
        ),
        isNull,
      );
    });

    test('the three ceilings agree', () {
      // The form refuses past maxPlayback, the duration_ms CHECK in
      // 001_schema.sql allows up to 30000, and the player cuts at
      // maxPlayback. If these ever disagree, an upload the form accepted
      // fails at the insert with a constraint name.
      expect(SoundboardPlay.maxPlayback.inMilliseconds, 30000);
    });

    test('and the size cap is that ceiling written as bytes', () {
      // 30s of WAV at 44.1kHz/16-bit stereo is ~5.3 MB, and wav is in the
      // accepted list — so the byte cap only catches what was never a clip.
      expect(SoundboardRepository.maxBytes, 5 * 1024 * 1024);
    });
  });

  group('whose setting is whose', () {
    test('a person\'s soundboard is keyed apart from their voice', () {
      // Three keys for one person — voice, shared track, soundboard — so
      // turning one down never turns another down with it.
      const userId = 'u1';
      expect(ParticipantIdentity.soundboardSettingsKey(userId), isNot(userId));
      expect(
        ParticipantIdentity.soundboardSettingsKey(userId),
        isNot(ParticipantIdentity.soundShareSettingsKey('$userId~device')),
      );
    });

    test('and it does not depend on which device they pressed it on', () {
      // Keyed by user id, so the same person on a phone and a laptop is one
      // setting rather than two that have to be found separately.
      expect(
        ParticipantIdentity.soundboardSettingsKey(
          ParticipantIdentity.userIdOf('u1~laptop'),
        ),
        ParticipantIdentity.soundboardSettingsKey(
          ParticipantIdentity.userIdOf('u1~phone'),
        ),
      );
    });
  });
}
