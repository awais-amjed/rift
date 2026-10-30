import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/screens/settings/widgets/audio_device_picker.dart';

import 'helpers/memory_storage.dart';

void main() {
  setUpAll(() => HydratedBloc.storage = MemoryStorage());

  Future<Size> pickerSize(
    WidgetTester tester, {
    required bool loading,
    List<MediaDevice> devices = const [],
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
                  selectedDeviceId: null,
                  loading: loading,
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
}
