import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/voice_attributes.dart';
import 'package:rift/logic/services/watch_cues.dart';

void main() {
  const me = 'me~d1';
  const myStream = 'me~d1_screenshare';
  const theirStream = 'them~d2_screenshare';
  const otherStream = 'other~d3_screenshare';

  List<WatchCue> cues(
    Set<String>? previous,
    Set<String> current, {
    Set<String> watchedHere = const {},
    Set<String> live = const {me, myStream, theirStream, otherStream},
    String watcher = 'someone~d9',
  }) => watchCues(
    watcher: watcher,
    previous: previous,
    current: current,
    localIdentity: me,
    watchedHere: watchedHere,
    live: live,
  );

  group('watchCues', () {
    test('the sharer hears somebody start and stop watching', () {
      expect(cues({}, {myStream}), [WatchCue.started]);
      expect(cues({myStream}, {}), [WatchCue.stopped]);
    });

    test('a phone sharing on its voice connection is the sharer too', () {
      expect(cues({}, {me}), [WatchCue.started]);
    });

    test('somebody already watching hears a new watcher arrive', () {
      expect(cues({}, {theirStream}, watchedHere: {theirStream}), [
        WatchCue.started,
      ]);
    });

    test('a stream this client has nothing to do with is silent', () {
      expect(cues({}, {otherStream}, watchedHere: {theirStream}), isEmpty);
    });

    test('the first list seen is a baseline, not a change', () {
      expect(cues(null, {myStream}), isEmpty);
    });

    test('an unchanged list is silent', () {
      expect(cues({myStream}, {myStream}), isEmpty);
    });

    test('watchers leaving a stream that has ended are silent', () {
      expect(cues({myStream}, {}, live: {}), isEmpty);
      expect(cues({me}, {}, live: {}), isEmpty);
    });

    test('a sharer previewing their own stream is not an audience', () {
      const theirVoice = 'them~d2';
      expect(
        cues(
          {},
          {theirStream},
          watchedHere: {theirStream},
          watcher: theirVoice,
        ),
        isEmpty,
      );
      // A phone streams on its voice connection.
      expect(
        cues(
          {},
          {theirVoice},
          watchedHere: {theirVoice},
          watcher: theirVoice,
          live: {theirVoice},
        ),
        isEmpty,
      );
      // Anybody else opening that phone's stream is an audience.
      expect(
        cues({}, {theirVoice}, watchedHere: {theirVoice}, live: {theirVoice}),
        [WatchCue.started],
      );
    });

    test('switching streams stops one and starts the other', () {
      expect(cues({myStream}, {theirStream}, watchedHere: {theirStream}), [
        WatchCue.started,
        WatchCue.stopped,
      ]);
    });
  });

  group('VoiceAttributes watching', () {
    test('round-trips through the attribute', () {
      final attrs = VoiceAttributes.forSelf(
        deafened: false,
        watching: {theirStream, myStream},
        pushToTalkIdle: false,
      );
      expect(VoiceAttributes.watchingOf(attrs), {myStream, theirStream});
    });

    test('says whether a push-to-talk key is up', () {
      bool idle(bool up) => VoiceAttributes.isPushToTalkIdle(
        VoiceAttributes.forSelf(
          deafened: false,
          watching: {},
          pushToTalkIdle: up,
        ),
      );
      expect(idle(true), isTrue);
      expect(idle(false), isFalse);
      // A client from before the attribute: its track's own state stands.
      expect(VoiceAttributes.isPushToTalkIdle(const {}), isFalse);
    });

    test('is always published, even empty', () {
      final attrs = VoiceAttributes.forSelf(
        deafened: false,
        watching: {},
        pushToTalkIdle: false,
      );
      expect(attrs.containsKey(VoiceAttributes.watchingKey), isTrue);
      expect(VoiceAttributes.watchingOf(attrs), isEmpty);
    });

    test('reads anything unreadable as nothing', () {
      for (final raw in ['', 'not json', '{"a":1}', '[1,2]']) {
        expect(
          VoiceAttributes.watchingOf({VoiceAttributes.watchingKey: raw}),
          isEmpty,
        );
      }
      expect(VoiceAttributes.watchingOf({}), isEmpty);
    });
  });
}
