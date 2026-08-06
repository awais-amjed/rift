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

  group('ParticipantRoster.isSpeaking', () {
    final roster = [
      p('me', userId: 'u1', local: true, speaking: true),
      p('them', userId: 'u2'),
    ];

    test('answers from the roster, not from the caller', () {
      // The whole point: the grid tile used to read LiveKit's own flag, which
      // for the local user lags far behind the mic-level detection the roster
      // carries — so the tile stayed dark while the sidebar row glowed.
      expect(
        ParticipantRoster.isSpeaking(roster, 'me', fallback: false),
        isTrue,
      );
      expect(
        ParticipantRoster.isSpeaking(roster, 'them', fallback: true),
        isFalse,
      );
    });

    test('falls back for an identity the roster does not carry', () {
      // Before the first sync, and for the losing device of a multi-device
      // user, there is nothing to read — the caller's own value stands.
      expect(
        ParticipantRoster.isSpeaking(roster, 'stranger', fallback: true),
        isTrue,
      );
      expect(
        ParticipantRoster.isSpeaking(const [], 'me', fallback: true),
        isTrue,
      );
      expect(ParticipantRoster.isSpeaking(const [], 'me'), isFalse);
    });
  });
}
