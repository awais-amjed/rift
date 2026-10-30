import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/enums/noise_filter_priority.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/screens/settings/widgets/voice_audio/noise_filter_beta_options.dart';

/// Linux has Time critical and Normal and no Precise timing, and a priority
/// saved that it does not offer reads as Normal, which is what it runs.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    required bool windows,
    NoiseFilterPriority priority = NoiseFilterPriority.normal,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(extensions: [ThemeState()]),
      home: Scaffold(
        body: NoiseFilterBetaOptions(
          choices: NoiseFilterPriority.offered(windows: windows),
          priority: priority,
          preciseTiming: windows ? false : null,
          onPriorityChanged: (_) {},
          onPreciseTimingChanged: (_) {},
        ),
      ),
    ),
  );

  testWidgets('Windows shows Precise timing', (tester) async {
    await pump(tester, windows: true);
    expect(find.text('Precise timing'), findsOneWidget);
  });

  testWidgets('Linux hides Precise timing', (tester) async {
    await pump(tester, windows: false);
    expect(find.text('Noise filter priority'), findsOneWidget);
    expect(find.text('Precise timing'), findsNothing);
  });

  testWidgets('a priority Linux lacks shows as Normal', (tester) async {
    await pump(tester, windows: false, priority: NoiseFilterPriority.highest);
    expect(find.text('Normal'), findsOneWidget);
    expect(find.text('Highest'), findsNothing);
  });
}
