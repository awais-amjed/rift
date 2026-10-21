import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/logic/cubits/app/app_cubit.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/soundboard_volume_control.dart';
import 'package:rift/presentation/common/volume_readout.dart';

import 'helpers/memory_storage.dart';

/// The reset beside a volume's figure: offered only off 100%, it puts the
/// level back to 100%, and it keeps its place while hidden so the figure and
/// the track do not jump when a drag takes the level off 100%.
void main() {
  setUpAll(() => HydratedBloc.storage = MemoryStorage());

  Widget host(Widget child) => BlocProvider<ThemeCubit>(
    create: (_) => ThemeCubit(),
    child: MaterialApp(
      home: Scaffold(body: Center(child: child)),
    ),
  );

  final reset = find.byTooltip('Reset to 100%');
  bool shown(WidgetTester tester) => tester
      .widget<Visibility>(
        find.ancestor(of: reset, matching: find.byType(Visibility)),
      )
      .visible;

  testWidgets('offered off 100%, and sets 100%', (tester) async {
    final changes = <double>[];
    await tester.pumpWidget(
      host(
        VolumeReadout(
          value: 0.4,
          style: const TextStyle(),
          onChanged: changes.add,
        ),
      ),
    );
    expect(find.text('40%'), findsOneWidget);
    expect(shown(tester), isTrue);
    await tester.tap(reset);
    expect(changes, [1.0]);
  });

  testWidgets('hidden at 100% and while muted, in the same space', (
    tester,
  ) async {
    Future<Size> sizeAt(double value, {bool muted = false}) async {
      await tester.pumpWidget(
        host(
          VolumeReadout(
            value: value,
            muted: muted,
            width: 40,
            // The test font draws every glyph a square of its size: small
            // enough that "150%" fits the width, as it does in the app.
            style: const TextStyle(fontSize: 8),
            onChanged: (_) {},
          ),
        ),
      );
      return tester.getSize(find.byType(VolumeReadout));
    }

    final off = await sizeAt(1.5);
    expect(shown(tester), isTrue);
    // 99.8% reads 100%, so it has nothing to reset.
    expect(await sizeAt(0.998), off);
    expect(shown(tester), isFalse);
    expect(await sizeAt(0.4, muted: true), off);
    expect(shown(tester), isFalse);
    expect(find.text('—'), findsOneWidget);
  });

  testWidgets('the soundboard volume resets to 100%', (tester) async {
    final app = AppCubit()..setSoundboardVolume(0.6);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<ThemeCubit>(create: (_) => ThemeCubit()),
          BlocProvider<AppCubit>.value(value: app),
        ],
        child: const MaterialApp(
          home: Scaffold(body: SoundboardVolumeControl()),
        ),
      ),
    );
    await tester.tap(reset);
    await tester.pump();
    expect(app.state.soundboardVolume, 1.0);
    expect(find.text('100%'), findsOneWidget);
    expect(shown(tester), isFalse);
  });
}
