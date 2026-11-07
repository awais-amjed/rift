import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/share_ladder.dart';
import 'package:rift/logic/services/share_rung_follow.dart';
import 'package:rift/src/rust/api/screenshare/types.dart';

void main() {
  const h265 = VideoCodec.h265;
  const h264 = VideoCodec.h264;
  const vp9 = VideoCodec.vp9;
  const ShareWatcher gpu = (name: 'Ana', plays: {h265, h264, vp9});
  const ShareWatcher web = (name: 'Sam', plays: {h264, vp9});

  late List<VideoCodec> moves;
  late ShareRungFollow follow;

  setUp(() {
    moves = [];
    follow = ShareRungFollow(onMove: moves.add);
  });

  void at(VideoCodec current, List<ShareWatcher> watchers) =>
      follow.update(top: h265, current: current, watchers: watchers);

  test('goes down at once', () {
    fakeAsync((time) {
      at(h265, const [web]);
      expect(moves, [h264]);
    });
  });

  test('stays put when everyone plays it', () {
    fakeAsync((time) {
      at(h265, const [gpu]);
      time.elapse(const Duration(minutes: 5));
      expect(moves, isEmpty);
    });
  });

  test('goes back up only after the wait', () {
    fakeAsync((time) {
      at(h264, const []);
      time.elapse(ShareRungFollow.climbAfter - const Duration(seconds: 1));
      expect(moves, isEmpty);
      time.elapse(const Duration(seconds: 1));
      expect(moves, [h265]);
    });
  });

  test('somebody needing it again cancels the climb', () {
    fakeAsync((time) {
      at(h264, const []);
      time.elapse(const Duration(seconds: 20));
      at(h264, const [web]);
      expect(follow.climbing, isFalse);
      time.elapse(const Duration(minutes: 5));
      expect(moves, isEmpty);
    });
  });

  test('the wait starts over after a return', () {
    fakeAsync((time) {
      at(h264, const []);
      time.elapse(const Duration(seconds: 20));
      at(h264, const [web]);
      at(h264, const []);
      time.elapse(const Duration(seconds: 20));
      expect(moves, isEmpty);
      time.elapse(const Duration(seconds: 10));
      expect(moves, [h265]);
    });
  });

  test('another change during the wait does not restart it', () {
    fakeAsync((time) {
      at(h264, const []);
      time.elapse(const Duration(seconds: 20));
      at(h264, const [gpu]);
      time.elapse(const Duration(seconds: 10));
      expect(moves, [h265]);
    });
  });

  test('a climb goes where the latest watchers allow', () {
    fakeAsync((time) {
      const ShareWatcher vp9Only = (name: 'Lee', plays: {vp9});
      at(vp9, const [web]);
      time.elapse(const Duration(seconds: 10));
      at(vp9, const []);
      time.elapse(const Duration(seconds: 20));
      expect(moves, [h265]);
      at(h265, const [vp9Only]);
      expect(moves, [h265, vp9]);
    });
  });

  test('going down cancels a climb that was waiting', () {
    fakeAsync((time) {
      at(h264, const []);
      at(h264, const [
        (name: 'Lee', plays: {vp9}),
      ]);
      expect(moves, [vp9]);
      expect(follow.climbing, isFalse);
      time.elapse(const Duration(minutes: 5));
      expect(moves, [vp9]);
    });
  });

  test('never climbs above the top', () {
    fakeAsync((time) {
      follow.update(top: h264, current: h264, watchers: const [gpu]);
      time.elapse(const Duration(minutes: 5));
      expect(moves, isEmpty);
    });
  });

  test('a cancel at the end of the share stops the climb', () {
    fakeAsync((time) {
      at(h264, const []);
      follow.cancel();
      time.elapse(const Duration(minutes: 5));
      expect(moves, isEmpty);
    });
  });
}
