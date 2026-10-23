import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../../logic/services/host_platform.dart';
import '../../../../logic/services/mic_volume.dart';
import 'audio_device_section.dart';
import 'mic_test/mic_test_section.dart';
import 'section_divider.dart';
import 'section_title.dart';
import 'settings_tab.dart';
import 'voice_audio/audio_ducking_section.dart';
import 'voice_audio/audio_processing_section.dart';
import 'voice_audio/mic_volume_control.dart';
import 'voice_audio/output_volume_section.dart';
import 'voice_audio/soundboard_section.dart';
import 'voice_audio/sounds/sounds_section.dart';

/// The Voice & Audio settings tab: devices, the mic with its volume and test
/// and how it is cleaned up, call volume and on Windows other apps' volume
/// during calls, then the soundboard and Rift's own sounds as this device
/// hears them. The keys for push-to-talk, mute and deafen are Keybinds'.
class VoiceAudioContent extends StatelessWidget {
  /// A section to scroll to and light up, for someone sent here to it.
  final SettingsSection? focus;

  const VoiceAudioContent({super.key, this.focus});

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
            // Most-reached first: which mic and speakers, whether the mic
            // works, how it is cleaned up — right under the test, so a change
            // is heard while it runs — then how others sound, and the long
            // list of Rift's own sounds last.
            if (_canPickDevices) ...[
              const AudioDeviceSection(),
              const SectionDivider(),
            ],
            const SectionTitle(label: 'Microphone'),
            const SizedBox(height: 12),
            if (MicVolume.adjustable) ...[
              const MicVolumeControl(),
              const SizedBox(height: 20),
            ],
            const MicTestSection(),
            const SectionDivider(),
            AudioProcessingSection(appState: appState),
            const SectionDivider(),
            const OutputVolumeSection(),
            if (HostPlatform.ducksOtherApps) ...[
              const SectionDivider(),
              AudioDuckingSection(highlight: focus == SettingsSection.ducking),
            ],
            const SectionDivider(),
            SoundboardSection(appState: appState),
            const SectionDivider(),
            SoundsSection(appState: appState),
          ],
        );
      },
    );
  }
}
