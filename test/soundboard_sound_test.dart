import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/soundboard_sound.dart';
import 'package:rift/data/participant_identity.dart';
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
      expect(
        SoundboardStaging.rejectionFor(
          fileName: 'long.mp3',
          mime: 'audio/mpeg',
          bytes: 900 * 1024,
        ),
        isNotNull,
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
    });

    test('a clip longer than the ceiling says what will be heard', () {
      // Every listener cuts one off at maxPlayback, so a 30-second upload
      // printed as 30.0 s is a number nobody in the call experiences.
      expect(
        SoundboardStaging.cutoffLabel(const Duration(seconds: 30)),
        'plays 8.0 s',
      );
    });

    test('and one inside it says nothing at all', () {
      // The qualifier is the exception. On every row it would be noise.
      expect(SoundboardStaging.cutoffLabel(const Duration(seconds: 2)), isNull);
      expect(SoundboardStaging.cutoffLabel(SoundboardPlay.maxPlayback), isNull);
      expect(SoundboardStaging.cutoffLabel(Duration.zero), isNull);
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
