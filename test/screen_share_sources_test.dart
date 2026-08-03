import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/screen_share_sources.dart';
import 'package:rift/src/rust/api/screenshare/types.dart';

CaptureSource src(int index, {int? pid}) =>
    CaptureSource(index: index, title: 'source $index', audioSourcePid: pid);

void main() {
  group('ScreenShareSources.pickCaptureSource', () {
    test('keeps the source the user picked last time', () {
      final picked = ScreenShareSources.pickCaptureSource([
        src(1),
        src(7, pid: 4242),
        src(9),
      ], 7);
      expect(picked?.index, 7);
      expect(picked?.audioSourcePid, 4242);
    });

    test('falls back to the first when that window is gone', () {
      final picked = ScreenShareSources.pickCaptureSource([src(3), src(4)], 7);
      expect(picked?.index, 3);
    });

    test('falls back to the first when nothing was persisted', () {
      expect(
        ScreenShareSources.pickCaptureSource([src(3), src(4)], null)?.index,
        3,
      );
    });

    test('picks nothing when there are no sources', () {
      expect(ScreenShareSources.pickCaptureSource([], 7), isNull);
      expect(ScreenShareSources.pickCaptureSource([], null), isNull);
    });
  });
}
