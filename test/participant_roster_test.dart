import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/participant_info.dart';
import 'package:rift/logic/services/participant_roster.dart';
import 'package:rift/logic/services/voice_attributes.dart';

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

  // The sidebar drew a deafened person's headphones; their tile showed only a
  // crossed microphone, which reads as "muted, but listening".
  test('ParticipantRoster.isDeafened, by choice or by a moderator', () {
    final base = p('a', userId: 'u1');
    final roster = [
      ParticipantInfo(
        identity: 'self',
        userId: 'u1',
        name: 'u1',
        isSpeaking: false,
        isMicrophoneEnabled: false,
        isCameraEnabled: false,
        isLocal: false,
        isDeafened: true,
      ),
      ParticipantInfo(
        identity: 'mod',
        userId: 'u2',
        name: 'u2',
        isSpeaking: false,
        isMicrophoneEnabled: false,
        isCameraEnabled: false,
        isLocal: false,
        isServerDeafened: true,
      ),
      base,
    ];
    expect(ParticipantRoster.isDeafened(roster, 'self'), isTrue);
    expect(ParticipantRoster.isDeafened(roster, 'mod'), isTrue);
    expect(ParticipantRoster.isDeafened(roster, 'a'), isFalse);
    expect(ParticipantRoster.isDeafened(roster, 'stranger'), isFalse);
  });

  test('a share reads as paused only while its attribute says so', () {
    expect(VoiceAttributes.isSharePaused(const {'paused': 'true'}), isTrue);
    expect(VoiceAttributes.isSharePaused(const {'paused': 'false'}), isFalse);
    expect(VoiceAttributes.isSharePaused(const {}), isFalse);
    final roster = [
      const ParticipantInfo(
        identity: 'u1~d_screenshare',
        userId: 'u1',
        name: 'u1',
        isScreenshare: true,
        isSharePaused: true,
      ),
      p('u1~d', userId: 'u1'),
    ];
    expect(ParticipantRoster.isSharePaused(roster, 'u1~d_screenshare'), isTrue);
    expect(ParticipantRoster.isSharePaused(roster, 'u1~d'), isFalse);
    expect(ParticipantRoster.isSharePaused(roster, 'stranger'), isFalse);
  });

  test('a share\'s badge reads what the sharer says it sends', () {
    String? label(Map<String, String> a) =>
        VoiceAttributes.sentPictureOf(a)?.qualityLabel;
    expect(label(const {'size': '1920x1080', 'fps': '60'}), '1080p · 60fps');
    // A window shared at its own size is still named by its class.
    expect(label(const {'size': '1920x1048', 'fps': '30'}), '1080p · 30fps');
    expect(label(const {'size': '1280x720'}), '720p');
    expect(label(const {'size': '4096x1152', 'fps': '60'}), '1440p · 60fps');
    expect(label(const {}), isNull);
    expect(label(const {'size': 'garbage', 'fps': '60'}), isNull);
    expect(label(const {'size': '0x0', 'fps': '60'}), isNull);

    final roster = [
      const ParticipantInfo(
        identity: 'u1~d_screenshare',
        userId: 'u1',
        name: 'u1',
        isScreenshare: true,
        shareQuality: '1080p · 60fps',
      ),
      p('u1~d', userId: 'u1'),
    ];
    expect(
      ParticipantRoster.shareQuality(roster, 'u1~d_screenshare'),
      '1080p · 60fps',
    );
    expect(ParticipantRoster.shareQuality(roster, 'u1~d'), isNull);
    expect(ParticipantRoster.shareQuality(roster, 'stranger'), isNull);
  });
}
