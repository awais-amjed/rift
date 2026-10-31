import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rift/presentation/screens/settings/widgets/settings_content_scroll.dart';

/// A tab whose height can change after it opens, as a device list does.
class _Tab extends StatelessWidget {
  final ValueNotifier<double> height;

  const _Tab(this.height);

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double>(
    valueListenable: height,
    builder: (_, h, _) => SizedBox(height: h, width: 300),
  );
}

void main() {
  late List<double> reported;

  Future<ValueNotifier<double>> open(
    WidgetTester tester, {
    required double offset,
    required double height,
  }) async {
    reported = [];
    final tabHeight = ValueNotifier(height);
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 600,
          child: SettingsContentScroll(
            initialOffset: offset,
            onScrolled: reported.add,
            padding: EdgeInsets.zero,
            child: _Tab(tabHeight),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tabHeight;
  }

  double offsetOf(WidgetTester tester) =>
      tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels;

  testWidgets('opens where the tab was left', (tester) async {
    await open(tester, offset: 900, height: 3000);
    expect(offsetOf(tester), 900);
  });

  testWidgets('a tab that grows after opening is followed down', (
    tester,
  ) async {
    final height = await open(tester, offset: 1200, height: 1000);
    // As far as the short tab reaches, and still meaning to go further.
    expect(offsetOf(tester), 400);
    // Closed now, it would still come back to 1200: nothing said otherwise.
    expect(reported.where((offset) => offset != 1200), isEmpty);

    height.value = 3000;
    await tester.pumpAndSettle();
    expect(offsetOf(tester), 1200);

    // There: growing again moves nothing.
    height.value = 5000;
    await tester.pumpAndSettle();
    expect(offsetOf(tester), 1200);
  });

  testWidgets('scrolling by hand stops the way back', (tester) async {
    final height = await open(tester, offset: 1200, height: 1000);
    await tester.drag(find.byType(Scrollable), const Offset(0, 300));
    await tester.pumpAndSettle();
    final mine = offsetOf(tester);
    expect(mine, lessThan(400));

    height.value = 3000;
    await tester.pumpAndSettle();
    expect(offsetOf(tester), mine);
    expect(reported.last, mine);
  });

  testWidgets('a tab opened fresh starts at its top', (tester) async {
    await open(tester, offset: 0, height: 3000);
    expect(offsetOf(tester), 0);
  });
}
