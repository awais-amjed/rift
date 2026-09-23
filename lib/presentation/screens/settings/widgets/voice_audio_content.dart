import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../../logic/services/host_platform.dart';
import '../../../theme/theme_context.dart';
import 'audio_device_section.dart';
import 'mic_test/mic_test_section.dart';
import 'section_title.dart';
import 'setting_toggle_row.dart';
import 'voice_audio/audio_processing_section.dart';
import 'voice_audio/push_to_talk_section.dart';
import 'voice_audio/soundboard_section.dart';
import 'voice_audio/sounds/sounds_section.dart';

/// The Voice & Audio settings tab: devices, mic processing, the mic test,
/// the soundboard and Rift's own sounds as this device hears them, and the two Windows-only
/// sections.
class VoiceAudioContent extends StatelessWidget {
  const VoiceAudioContent({super.key});

  /// Picking an input and an output by name is a desktop idea, and on a phone
  /// it is two dead controls: WebRTC's Android device module does not
  /// enumerate playout devices at all, so Output reads "No devices found"
  /// forever, and Input offers nothing but "System Default". Routing there
  /// belongs to the OS and to LiveKit's own audio switch, which follow the
  /// headset being plugged in without being asked.
  ///
  /// The processing toggles and the mic test below stay: those are about the
  /// signal, not about which socket it came from, and they work everywhere.
  static final bool _canPickDevices = !HostPlatform.isMobile;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppCubit, AppState>(
      builder: (context, appState) {
        // The reading measure this pane used to set for itself is
        // [K.settingsMeasure] now, applied by the settings screen to every
        // pane — this one was the only one that had it.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_canPickDevices) ...[
              const AudioDeviceSection(),
              _divider(context),
            ],
            AudioProcessingSection(appState: appState),
            const SizedBox(height: 20),
            const MicTestSection(),
            _divider(context),
            SoundboardSection(appState: appState),
            _divider(context),
            SoundsSection(appState: appState),
            // The divider belongs to what follows, not to what precedes
            // it: on anything but Windows there is nothing after this and
            // the rule was hanging under the last control.
            if (HostPlatform.ducksOtherApps) ...[
              _divider(context),
              const SectionTitle(label: 'Audio ducking'),
              const SizedBox(height: 12),
              SettingToggleRow(
                title: 'Disable automatic volume lowering',
                description:
                    "Windows lowers other apps' volume when a call is "
                    'active. Enable this to prevent that.',
                value: appState.disableAudioDucking,
                onChanged: context.read<AppCubit>().setDisableAudioDucking,
              ),
            ],
            if (HostPlatform.hasPushToTalk) ...[
              _divider(context),
              PushToTalkSection(appState: appState),
            ],
          ],
        );
      },
    );
  }

  Widget _divider(BuildContext context) => Column(
    children: [
      const SizedBox(height: 24),
      Divider(color: context.theme.borderPrimary),
      const SizedBox(height: 16),
    ],
  );
}
