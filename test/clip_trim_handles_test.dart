import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/screens/home/call_clip/widgets/clip_trim_handles.dart';

/// The trim view's waveform: only a drag from a handle moves it, the two
/// never cross, and anywhere else a click or drag moves the play line.
void main() {
  late List<(double, double)> moves;
  late List<double> seeks;
  late List<String> scrubs;

  Future<void> pump(
    WidgetTester tester, {
    double start = 0,
    double end = 1,
    double minGap = 0.1,
  }) async {
    moves = [];
    seeks = [];
    scrubs = [];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [ThemeState()]),
        home: Center(
          child: SizedBox(
            width: 400,
            height: 80,
            child: ClipTrimHandles(
              start: start,
              end: end,
              minGap: minGap,
              onChanged: (s, e) => moves.add((s, e)),
              onSeek: seeks.add,
              onScrubStart: () => scrubs.add('start'),
              onScrubEnd: () => scrubs.add('end'),
            ),
          ),
        ),
      ),
    );
  }

  Offset at(WidgetTester tester, double fraction) {
    final box = tester.getRect(find.byType(ClipTrimHandles));
    return Offset(box.left + box.width * fraction, box.center.dy);
  }

  testWidgets('a click puts the play line there and leaves the selection', (
    tester,
  ) async {
    // A click used to move the nearer handle, so trying to hear a moment cut
    // the selection down to it.
    await pump(tester, start: 0.1, end: 0.9);
    await tester.tapAt(at(tester, 0.3));
    expect(moves, isEmpty);
    expect(seeks.single, closeTo(0.3, 0.001));
  });

  testWidgets('a drag away from the handles scrubs the line', (tester) async {
    await pump(tester, start: 0.1, end: 0.9);
    await tester.dragFrom(at(tester, 0.4), const Offset(80, 0));
    expect(moves, isEmpty);
    expect(scrubs, ['start', 'end']);
    expect(seeks.first, closeTo(0.4, 0.001));
    expect(seeks.last, closeTo(0.6, 0.001));
  });

  testWidgets('a drag from the end handle moves the end', (tester) async {
    await pump(tester, start: 0.1, end: 0.9);
    await tester.dragFrom(at(tester, 0.9), const Offset(-80, 0));
    expect(seeks, isEmpty);
    expect(moves.last.$1, 0.1);
    expect(moves.last.$2, closeTo(0.7, 0.001));
  });

  testWidgets('a drag from just beside a handle still takes it', (
    tester,
  ) async {
    await pump(tester, start: 0.25, end: 0.9);
    final grab = at(tester, 0.25) + const Offset(ClipTrimHandles.reach - 2, 0);
    await tester.dragFrom(grab, const Offset(40, 0));
    expect(seeks, isEmpty);
    expect(moves.last.$1, closeTo(0.25 + 40 / 400, 0.01));
  });

  testWidgets('the start stops short of the end', (tester) async {
    await pump(tester, start: 0.4, end: 0.5);
    await tester.dragFrom(at(tester, 0.4), const Offset(200, 0));
    expect(moves.last.$1, closeTo(0.4, 0.001));
    expect(moves.last.$2, 0.5);
  });

  testWidgets('a drag past the edge stops at it', (tester) async {
    await pump(tester, start: 0.2, end: 0.9);
    await tester.dragFrom(at(tester, 0.9), const Offset(300, 0));
    expect(moves.last.$2, 1);
  });
}
