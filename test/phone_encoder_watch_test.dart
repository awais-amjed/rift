import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show StatsReport;
import 'package:rift/logic/services/phone_encoder_watch.dart';

void main() {
  /// A sender's reports as libwebrtc gave them on Nov 6 2026: both pictures, and
  /// the codec each points at.
  List<StatsReport> sending(String mime) => [
    StatsReport('out-q', 'outbound-rtp', 0, {'codecId': 'c1', 'rid': 'q'}),
    StatsReport('out-h', 'outbound-rtp', 0, {'codecId': 'c1', 'rid': 'h'}),
    StatsReport('c1', 'codec', 0, {'mimeType': mime}),
  ];

  group('whether a sender left its codec', () {
    test('a sender on what was published has not', () {
      expect(
        PhoneEncoderWatch.leftItsCodec('h264', sending('video/H264')),
        isFalse,
      );
    });

    test('a sender moved to another codec has', () {
      expect(
        PhoneEncoderWatch.leftItsCodec('h264', sending('video/VP8')),
        isTrue,
      );
    });

    test('the two may spell a codec differently', () {
      expect(
        PhoneEncoderWatch.leftItsCodec('H264', sending('video/h264')),
        isFalse,
      );
    });

    test('a codec it reads through the sender, not the first one listed', () {
      final reports = [
        StatsReport('old', 'codec', 0, {'mimeType': 'video/H264'}),
        ...sending('video/VP8'),
      ];

      expect(PhoneEncoderWatch.leftItsCodec('h264', reports), isTrue);
    });

    test('not knowing either side is no failure', () {
      expect(PhoneEncoderWatch.leftItsCodec('', sending('video/VP8')), isFalse);
      expect(PhoneEncoderWatch.leftItsCodec('h264', const []), isFalse);
      expect(
        PhoneEncoderWatch.leftItsCodec('h264', [
          StatsReport('out', 'outbound-rtp', 0, {'codecId': 'gone'}),
        ]),
        isFalse,
      );
    });
  });

  group('the watch', () {
    late bool left;
    late bool sharing;
    late bool inFront;
    late int failed;
    late int seen;

    setUp(() {
      left = false;
      sharing = true;
      inFront = true;
      failed = 0;
      seen = 0;
    });

    PhoneEncoderWatch watch() => PhoneEncoderWatch(
      leftItsCodec: () async => left,
      stillSharing: () => sharing,
      inFront: () => inFront,
      onFailed: () => failed++,
      onSeen: () => seen++,
    )..start();

    test('a healthy share says nothing', () {
      fakeAsync((time) {
        watch();
        time.elapse(const Duration(minutes: 5));
        expect(failed, 0);
        expect(seen, 0);
      });
    });

    test('a failure says so once, however long the share goes on', () {
      fakeAsync((time) {
        watch();
        time.elapse(const Duration(seconds: 10));
        left = true;
        time.elapse(const Duration(minutes: 5));
        expect(failed, 1);
        expect(seen, 1);
      });
    });

    test('in another app, the toast waits and the rest does not', () {
      fakeAsync((time) {
        inFront = false;
        left = true;
        watch();
        time.elapse(const Duration(minutes: 1));
        expect(failed, 1);
        expect(seen, 0);

        inFront = true;
        time.elapse(const Duration(seconds: 3));
        expect(failed, 1);
        expect(seen, 1);
      });
    });

    test('a share that ended is not reported', () {
      fakeAsync((time) {
        inFront = false;
        left = true;
        watch();
        time.elapse(const Duration(seconds: 3));
        sharing = false;
        inFront = true;
        time.elapse(const Duration(minutes: 1));
        expect(seen, 0);
      });
    });

    test('stopping while the answer is on its way drops it', () {
      fakeAsync((time) {
        final answer = Completer<bool>();
        final running = PhoneEncoderWatch(
          leftItsCodec: () => answer.future,
          stillSharing: () => sharing,
          inFront: () => inFront,
          onFailed: () => failed++,
          onSeen: () => seen++,
        )..start();
        time.elapse(const Duration(seconds: 3));
        running.stop();
        answer.complete(true);
        time.flushMicrotasks();
        expect(failed, 0);
        expect(seen, 0);
      });
    });
  });
}
