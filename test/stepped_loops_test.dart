import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rift/presentation/common/loading_dots.dart';
import 'package:rift/presentation/screens/home/participants_grid/participants_tile/sound_wave_indicator.dart';

/// The loops step on a timer rather than animate: an animation draws a frame
/// on every vsync, which for dots waiting minutes on a roster was 16.9% of a
/// core on screen against 4.2% stepped (Nov 15, Linux). And they stop where
/// animations do, while nobody can see Rift (`AppSeenListener`'s
/// `TickerMode`), which a timer does not hear by itself.
void main() {
  final loops = <String, Widget>{
    'LoadingDots': const LoadingDots(color: Color(0xFFFFFFFF)),
    'SoundWaveIndicator': const SoundWaveIndicator(
      playing: true,
      color: Color(0xFFFFFFFF),
    ),
  };

  Future<void> pumpLoop(WidgetTester tester, Widget loop, bool on) =>
      tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: TickerMode(enabled: on, child: loop),
          ),
        ),
      );

  for (final MapEntry(key: name, value: loop) in loops.entries) {
    group(name, () {
      testWidgets('runs no animation', (tester) async {
        await pumpLoop(tester, loop, true);
        expect(tester.binding.transientCallbackCount, 0);
      });

      testWidgets('asks for a frame a step at a time', (tester) async {
        await pumpLoop(tester, loop, true);
        expect(tester.binding.hasScheduledFrame, isFalse);
        // The clock moves on with no frame drawn, as between vsyncs.
        await tester.binding.delayed(const Duration(milliseconds: 200));
        expect(tester.binding.hasScheduledFrame, isTrue);
      });

      testWidgets('stops while tickers are off', (tester) async {
        await pumpLoop(tester, loop, false);
        await tester.binding.delayed(const Duration(seconds: 2));
        expect(tester.binding.hasScheduledFrame, isFalse);

        await pumpLoop(tester, loop, true);
        await tester.binding.delayed(const Duration(milliseconds: 200));
        expect(tester.binding.hasScheduledFrame, isTrue);
      });
    });
  }
}
