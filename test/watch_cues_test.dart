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
  }) => watchCues(
    previous: previous,
    current: current,
    localIdentity: me,
    watchedHere: watchedHere,
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
      expect(
        cues({}, {theirStream}, watchedHere: {theirStream}),
        [WatchCue.started],
      );
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

    test('switching streams stops one and starts the other', () {
      expect(
        cues({myStream}, {theirStream}, watchedHere: {theirStream}),
        [WatchCue.started, WatchCue.stopped],
      );
    });
  });

  group('VoiceAttributes watching', () {
    test('round-trips through the attribute', () {
      final attrs = VoiceAttributes.forSelf(
        deafened: false,
        watching: {theirStream, myStream},
      );
      expect(VoiceAttributes.watchingOf(attrs), {myStream, theirStream});
    });

    test('is always published, even empty', () {
      final attrs = VoiceAttributes.forSelf(deafened: false, watching: {});
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
