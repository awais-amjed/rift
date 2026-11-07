import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/share_ladder.dart';
import 'package:rift/logic/services/voice_attributes.dart';
import 'package:rift/src/rust/api/screenshare/types.dart';

void main() {
  const h265 = VideoCodec.h265;
  const h264 = VideoCodec.h264;
  const vp9 = VideoCodec.vp9;
  const vp8 = VideoCodec.vp8;

  ShareWatcher watcher(String name, Set<VideoCodec> plays) =>
      (name: name, plays: plays);

  group('ShareLadder.rungFor', () {
    test('stays at the top with nobody watching', () {
      expect(ShareLadder.rungFor(top: h265, watchers: const []), h265);
      expect(ShareLadder.rungFor(top: vp9, watchers: const []), vp9);
    });

    test('stays at the top when everyone plays it', () {
      final all = watcher('Sam', {h265, h264, vp9, vp8});
      expect(ShareLadder.rungFor(top: h265, watchers: [all]), h265);
    });

    test('takes the best rung every watcher plays', () {
      expect(
        ShareLadder.rungFor(
          top: h265,
          watchers: [
            watcher('Sam', {h265, h264, vp9, vp8}),
            watcher('Ana', {h264, vp9, vp8}),
          ],
        ),
        h264,
      );
      expect(
        ShareLadder.rungFor(
          top: h265,
          watchers: [
            watcher('Sam', {h264, vp8}),
            watcher('Ana', {vp9, vp8}),
          ],
        ),
        vp8,
      );
    });

    test('never goes above what was picked', () {
      final all = watcher('Sam', {h265, h264, vp9, vp8});
      expect(ShareLadder.rungFor(top: vp9, watchers: [all]), vp9);
      expect(ShareLadder.rungFor(top: vp8, watchers: [all]), vp8);
      expect(ShareLadder.rungFor(top: h264, watchers: [all]), h264);
    });

    test('a hand-picked VP9 only ever drops to VP8', () {
      expect(
        ShareLadder.rungFor(
          top: vp9,
          watchers: [
            watcher('Sam', {h264, vp8}),
          ],
        ),
        vp8,
      );
    });

    test('VP8 is the floor, even for one who plays nothing known', () {
      expect(
        ShareLadder.rungFor(top: h265, watchers: [watcher('Sam', const {})]),
        vp8,
      );
    });

    test('an old Rift, which says nothing, brings H265 down to H264', () {
      expect(
        ShareLadder.rungFor(
          top: h265,
          watchers: [watcher('Sam', VoiceAttributes.playsOf(const {}))],
        ),
        h264,
      );
    });
  });

  group('who the note names', () {
    final watchers = [
      watcher('Sam', {h264, vp9, vp8}),
      watcher('Ana', {h265, h264, vp9, vp8}),
      watcher('Lee', {vp8}),
    ];

    test('those who could not play the rung above', () {
      expect(ShareLadder.holdingAt(h264, watchers), ['Sam', 'Lee']);
      expect(ShareLadder.holdingAt(vp8, watchers), ['Lee']);
      expect(ShareLadder.holdingAt(h265, watchers), isEmpty);
    });

    test('in words', () {
      expect(ShareLadder.whoFor(const ['Sam']), 'Sam');
      expect(ShareLadder.whoFor(const ['Sam', 'Ana']), 'Sam and Ana');
      expect(ShareLadder.whoFor(const ['Sam', 'Ana', 'Lee']), '3 people');
    });
  });

  group('VoiceAttributes plays', () {
    test('round-trips through the attribute', () {
      final attrs = VoiceAttributes.forSelf(
        deafened: false,
        watching: const {},
        pushToTalkIdle: false,
        plays: const {h265, vp8},
      );
      expect(VoiceAttributes.playsOf(attrs), {h265, vp8});
    });

    test('anything unreadable counts as not having said', () {
      for (final raw in ['', 'nonsense', '{"a":1}']) {
        expect(
          VoiceAttributes.playsOf({VoiceAttributes.playsKey: raw}),
          VoiceAttributes.playsUnsaid,
        );
      }
    });

    test('not having said never includes H265', () {
      expect(VoiceAttributes.playsUnsaid, isNot(contains(h265)));
    });

    test('a codec this build does not know is passed over', () {
      expect(
        VoiceAttributes.playsOf({VoiceAttributes.playsKey: '["av1","vp9"]'}),
        {vp9},
      );
    });
  });
}
