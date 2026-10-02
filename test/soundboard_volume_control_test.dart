import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/logic/cubits/app/app_cubit.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/soundboard_volume_control.dart';

/// In-memory stand-in so the hydrated cubits can be built in tests.
class _MemoryStorage implements Storage {
  final Map<String, dynamic> _data = {};

  @override
  dynamic read(String key) => _data[key];

  @override
  Future<void> write(String key, dynamic value) async => _data[key] = value;

  @override
  Future<void> delete(String key) async => _data.remove(key);

  @override
  Future<void> clear() async => _data.clear();

  @override
  Future<void> close() async {}
}

/// F-7: muting everyone else greyed the volume out and read 0, while your own
/// clips went on playing at the real volume with no way to turn them down.
void main() {
  setUpAll(() => HydratedBloc.storage = _MemoryStorage());

  testWidgets('the volume stays live while everyone else is muted', (
    tester,
  ) async {
    final app = AppCubit()
      ..setSoundboardVolume(0.6)
      ..setSoundboardMuted(true);
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

    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.onChanged, isNotNull);
    expect(slider.value, 0.6);
    expect(find.text('60%'), findsOneWidget);
    expect(find.textContaining('Only your own clips'), findsOneWidget);

    slider.onChanged!(0.25);
    await tester.pump();
    expect(app.state.soundboardVolume, 0.25);
    expect(find.text('25%'), findsOneWidget);
  });
}
