import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/logic/services/call_clip/clip_trim.dart';
import 'package:rift/presentation/screens/home/call_clip/call_clip_dialog.dart';
import 'package:rift/presentation/screens/home/servers/manage/panels/soundboard/add_clip_form.dart';

import 'support/memory_storage.dart';

/// Stereo frames i = (i, -i): which frames a cut kept can be read off them.
Int16List ramp(int frames) => Int16List.fromList([
  for (var i = 0; i < frames; i++) ...[i, -i],
]);

void main() {
  group('cut', () {
    test('keeps exactly the frames between start and end', () {
      final out = ClipTrim.cut(
        ramp(100),
        2,
        const Duration(milliseconds: 200),
        const Duration(milliseconds: 500),
        rate: 100,
      );
      expect(out.length, 30 * 2);
      expect(out.first, 20);
      expect(out[1], -20);
      expect(out[out.length - 2], 49);
    });

    test('an end past the clip stops at its end', () {
      final out = ClipTrim.cut(
        ramp(100),
        2,
        const Duration(milliseconds: 900),
        const Duration(seconds: 5),
        rate: 100,
      );
      expect(out.length, 10 * 2);
      expect(out[out.length - 2], 99);
    });

    test('a start before the clip starts at its start', () {
      final out = ClipTrim.cut(
        ramp(100),
        2,
        const Duration(milliseconds: -300),
        const Duration(milliseconds: 100),
        rate: 100,
      );
      expect(out.length, 10 * 2);
      expect(out.first, 0);
    });

    test('a start at or after the end gives nothing', () {
      expect(
        ClipTrim.cut(
          ramp(100),
          2,
          const Duration(milliseconds: 500),
          const Duration(milliseconds: 500),
          rate: 100,
        ),
        isEmpty,
      );
      expect(
        ClipTrim.cut(
          ramp(100),
          2,
          const Duration(milliseconds: 600),
          const Duration(milliseconds: 100),
          rate: 100,
        ),
        isEmpty,
      );
    });
  });

  group('peaks', () {
    test('one value a bucket, each between 0 and 1', () {
      final pcm = Int16List.fromList([
        for (var i = 0; i < 48000; i++) ...[
          (i.isEven ? 1 : -1) * (i % 32768),
          -32768,
        ],
      ]);
      final out = ClipTrim.peaks(pcm, 2, 200);
      expect(out, hasLength(200));
      expect(out.every((p) => p >= 0 && p <= 1), isTrue);
      expect(out.first, 1.0, reason: 'the right channel is at full scale');
    });

    test('silence is flat, and more buckets than frames still fills', () {
      expect(ClipTrim.peaks(Int16List(20), 2, 50), List.filled(50, 0.0));
      expect(ClipTrim.peaks(Int16List(0), 2, 8), List.filled(8, 0.0));
    });

    test('loud in the second half only shows there', () {
      final pcm = Int16List(2000 * 2);
      for (var i = 1000; i < 2000; i++) {
        pcm[i * 2] = 16384;
      }
      final out = ClipTrim.peaks(pcm, 2, 4);
      expect(out[0], 0);
      expect(out[1], 0);
      expect(out[2], closeTo(0.5, 0.001));
      expect(out[3], closeTo(0.5, 0.001));
    });
  });

  group('the play line', () {
    double at(
      Duration elapsed, {
      Duration length = const Duration(seconds: 4),
    }) => ClipTrim.playhead(
      start: 0.2,
      end: 0.6,
      elapsed: elapsed,
      length: length,
    );

    test('starts at the start of the selection', () {
      expect(at(Duration.zero), closeTo(0.2, 1e-9));
    });

    test('moves across the selection with the time played', () {
      expect(at(const Duration(seconds: 1)), closeTo(0.3, 1e-9));
      expect(at(const Duration(seconds: 2)), closeTo(0.4, 1e-9));
    });

    test('stops at the end, however late the timer is', () {
      expect(at(const Duration(seconds: 9)), closeTo(0.6, 1e-9));
    });

    test('a selection of no length stays at its start', () {
      expect(
        at(const Duration(seconds: 1), length: Duration.zero),
        closeTo(0.2, 1e-9),
      );
    });
  });

  group('Add to soundboard is offered', () {
    bool offers({
      bool fromDmCall = false,
      String? clip = 's1',
      String? scope = 's1',
      bool canManage = true,
    }) => CallClipDialog.offersAdd(
      fromDmCall: fromDmCall,
      clipServerId: clip,
      scopeServerId: scope,
      canManage: canManage,
    );

    test('on the server it was clipped on, to a manager', () {
      expect(offers(), isTrue);
    });

    test('never opened on another server', () {
      expect(offers(scope: 's2'), isFalse);
    });

    test('never once that server is off the list', () {
      expect(offers(clip: null), isFalse);
    });

    test('never from a DM call, or to somebody who may not manage it', () {
      expect(offers(fromDmCall: true), isFalse);
      expect(offers(canManage: false), isFalse);
    });
  });

  group('sizes', () {
    test('a WAV is its header and 4 bytes a frame', () {
      expect(
        ClipTrim.wavBytes(const Duration(seconds: 30)),
        44 + 30 * 48000 * 4,
      );
    });

    test('an MP3 is its bitrate times its length', () {
      expect(ClipTrim.mp3Bytes(const Duration(seconds: 30), 192), 720000);
    });

    test('a point in the clip reads as minutes, seconds and tenths', () {
      expect(ClipTrim.timeLabel(Duration.zero), '0:00.0');
      expect(
        ClipTrim.timeLabel(const Duration(seconds: 72, milliseconds: 349)),
        '1:12.3',
      );
      expect(ClipTrim.timeLabel(const Duration(minutes: 2)), '2:00.0');
    });

    test('the file is named for when it was clipped', () {
      expect(
        ClipTrim.fileName(DateTime(2026, 11, 21, 9, 5, 7), 'wav'),
        'rift-clip-20261121-090507.wav',
      );
    });
  });

  group('the soundboard form, handed a clip', () {
    setUp(() => HydratedBloc.storage = MemoryStorage());

    Future<void> pump(WidgetTester tester, Duration duration) =>
        tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(extensions: [ThemeState()]),
            home: Scaffold(
              body: AddClipForm(
                full: false,
                initial: (
                  bytes: Uint8List(1000),
                  fileName: 'rift-clip-20261121-090507.mp3',
                  mime: 'audio/mpeg',
                  duration: duration,
                ),
                onAdd:
                    ({
                      required name,
                      emoji,
                      required bytes,
                      required contentType,
                      required duration,
                    }) async => null,
              ),
            ),
          ),
        );

    testWidgets('over 30 seconds, it says to trim it', (tester) async {
      await pump(tester, const Duration(seconds: 31));
      expect(find.textContaining('Trim it first.'), findsOneWidget);
      expect(find.text('Add clip'), findsNothing);
    });

    testWidgets('within 30 seconds, it is ready to name and add', (
      tester,
    ) async {
      await pump(tester, const Duration(seconds: 12));
      expect(find.textContaining('Trim it first.'), findsNothing);
      expect(find.text('Add clip'), findsOneWidget);
      expect(find.text('rift-clip-20261121-090507'), findsOneWidget);
    });
  });
}
