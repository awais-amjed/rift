import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/participant_info.dart';
import 'package:rift/logic/services/participant_roster.dart';

ParticipantInfo p(
  String identity, {
  required String userId,
  bool local = false,
  bool speaking = false,
  bool mic = false,
  bool screenshare = false,
}) => ParticipantInfo(
  identity: identity,
  userId: userId,
  name: userId,
  isSpeaking: speaking,
  isMicrophoneEnabled: mic,
  isCameraEnabled: false,
  isLocal: local,
  isScreenshare: screenshare,
);

void main() {
  group('ParticipantRoster.dedupeByUser', () {
    test('one row per user across devices', () {
      final rows = ParticipantRoster.dedupeByUser([
        p('phone', userId: 'u1'),
        p('desktop', userId: 'u1'),
        p('other', userId: 'u2'),
      ]);
      expect(rows.length, 2);
      expect(rows.map((r) => r.userId).toSet(), {'u1', 'u2'});
    });

    test("a user's screenshare keeps its own row", () {
      final rows = ParticipantRoster.dedupeByUser([
        p('desktop', userId: 'u1'),
        p('desktop-screen', userId: 'u1', screenshare: true),
      ]);
      expect(rows.length, 2);
    });

    test('keeps the local device over a remote one', () {
      final rows = ParticipantRoster.dedupeByUser([
        p('remote', userId: 'u1', speaking: true, mic: true),
        p('local', userId: 'u1', local: true),
      ]);
      expect(rows.single.identity, 'local');
    });

    test('prefers the speaking device, then the unmuted one', () {
      expect(
        ParticipantRoster.dedupeByUser([
          p('quiet', userId: 'u1', mic: true),
          p('talking', userId: 'u1', speaking: true),
        ]).single.identity,
        'talking',
      );
      expect(
        ParticipantRoster.dedupeByUser([
          p('muted', userId: 'u1'),
          p('unmuted', userId: 'u1', mic: true),
        ]).single.identity,
        'unmuted',
      );
    });
  });
}
