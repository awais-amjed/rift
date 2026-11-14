import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/chat/fetching_latest_overlay.dart';

/// The pill over a saved copy says newer messages are coming, but only once
/// the fetch has taken long enough to notice, and it lets taps through.
void main() {
  final theme = ThemeState();

  double opacity(WidgetTester tester) => tester
      .widget<AnimatedOpacity>(
        find.ancestor(
          of: find.text('Loading new messages'),
          matching: find.byType(AnimatedOpacity),
        ),
      )
      .opacity;

  Widget frame({required bool fetching, VoidCallback? onTap}) => MaterialApp(
    theme: ThemeData(extensions: [theme]),
    home: FetchingLatestOverlay(
      fetching: fetching,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: const SizedBox.expand(),
      ),
    ),
  );

  testWidgets('a quick fetch never shows it', (tester) async {
    await tester.pumpWidget(frame(fetching: true));
    await tester.pump(const Duration(milliseconds: 100));
    expect(opacity(tester), 0);
    await tester.pumpWidget(frame(fetching: false));
    await tester.pump(const Duration(milliseconds: 400));
    expect(opacity(tester), 0);
  });

  testWidgets('a slow fetch shows it until the page lands', (tester) async {
    await tester.pumpWidget(frame(fetching: true));
    await tester.pump(const Duration(milliseconds: 300));
    expect(opacity(tester), 1);
    await tester.pumpWidget(frame(fetching: false));
    expect(opacity(tester), 0);
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('the rows under it still take taps', (tester) async {
    var taps = 0;
    await tester.pumpWidget(frame(fetching: true, onTap: () => taps++));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Loading new messages'), warnIfMissed: false);
    expect(taps, 1);
    await tester.pumpWidget(frame(fetching: false));
    await tester.pump(const Duration(milliseconds: 400));
  });
}
