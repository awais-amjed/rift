import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/screens/home/call_clip/widgets/clip_trim_handles.dart';

/// The trim view's handles: a press moves the nearer one, and the two never
/// cross.
void main() {
  Future<List<(double, double)>> pump(
    WidgetTester tester, {
    double start = 0,
    double end = 1,
    double minGap = 0.1,
  }) async {
    final moves = <(double, double)>[];
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
            ),
          ),
        ),
      ),
    );
    return moves;
  }

  Offset at(WidgetTester tester, double fraction) {
    final box = tester.getRect(find.byType(ClipTrimHandles));
    return Offset(box.left + box.width * fraction, box.center.dy);
  }

  testWidgets('a press near the end moves the end', (tester) async {
    final moves = await pump(tester);
    await tester.tapAt(at(tester, 0.8));
    expect(moves.last.$1, 0);
    expect(moves.last.$2, closeTo(0.8, 0.001));
  });

  testWidgets('a press near the start moves the start', (tester) async {
    final moves = await pump(tester);
    await tester.tapAt(at(tester, 0.3));
    expect(moves.last.$1, closeTo(0.3, 0.001));
    expect(moves.last.$2, 1);
  });

  testWidgets('the start stops short of the end', (tester) async {
    final moves = await pump(tester, start: 0.4, end: 0.5);
    await tester.dragFrom(at(tester, 0.4), const Offset(200, 0));
    expect(moves.last.$1, closeTo(0.4, 0.001));
    expect(moves.last.$2, 0.5);
  });

  testWidgets('a drag past the edge stops at it', (tester) async {
    final moves = await pump(tester, start: 0.2, end: 0.9);
    await tester.dragFrom(at(tester, 0.9), const Offset(300, 0));
    expect(moves.last.$2, 1);
  });
}
