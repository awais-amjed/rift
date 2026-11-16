import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rift/data/classes/sound_outputs.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/screens/settings/widgets/audio_device_picker.dart';

import 'helpers/memory_storage.dart';

void main() {
  setUpAll(() => HydratedBloc.storage = MemoryStorage());

  Future<Size> pickerSize(
    WidgetTester tester, {
    required bool loading,
    List<MediaDevice> devices = const [],
    String? selectedDeviceId,
    String? followLabel,
  }) async {
    await tester.pumpWidget(
      BlocProvider<ThemeCubit>(
        create: (_) => ThemeCubit(),
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 400,
                child: AudioDevicePicker(
                  label: 'Input device',
                  icon: Icons.mic_rounded,
                  devices: devices,
                  formats: const {},
                  selectedDeviceId: selectedDeviceId,
                  loading: loading,
                  followLabel: followLabel,
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return tester.getSize(find.byType(AudioDevicePicker));
  }

  // Loading used to be a line of text, shorter than the field that replaced
  // it, so everything under the pickers jumped when the lists landed.
  testWidgets('the loading picker is the height of the filled one', (
    tester,
  ) async {
    final loading = await pickerSize(tester, loading: true);
    expect(find.text('Loading devices…'), findsOneWidget);
    final filled = await pickerSize(
      tester,
      loading: false,
      devices: const [MediaDevice('mic', 'Microphone', 'audioinput', null)],
    );
    expect(loading.height, filled.height);
  });

  // A kind of sound split off the output (Voice & audio → Separate devices)
  // has three choices, and "System default" must not read as "same as
  // output": with the output on a headset they play in different places.
  group('a picker that can follow the output', () {
    const speakers = [MediaDevice('spk', 'Speakers', 'audiooutput', null)];

    testWidgets('shows following the output when nothing is chosen', (
      tester,
    ) async {
      await pickerSize(
        tester,
        loading: false,
        devices: speakers,
        followLabel: 'Same as output device',
      );
      expect(find.text('Same as output device'), findsOneWidget);
      expect(find.text('System default'), findsNothing);
    });

    testWidgets('shows the system default when that was chosen', (
      tester,
    ) async {
      await pickerSize(
        tester,
        loading: false,
        devices: speakers,
        selectedDeviceId: SoundOutputs.systemDefault,
        followLabel: 'Same as output device',
      );
      expect(find.text('System default'), findsOneWidget);
      expect(find.text('Same as output device'), findsNothing);
    });
  });
}
