import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import 'audio_device_section.dart';
import 'mic_test/mic_test_section.dart';
import 'section_title.dart';
import 'setting_toggle_row.dart';
import 'voice_audio/audio_processing_section.dart';
import 'voice_audio/push_to_talk_section.dart';

/// The Voice & Audio settings tab: devices, mic processing, the mic test,
/// and the two Windows-only sections.
class VoiceAudioContent extends StatelessWidget {
  final ThemeState themeState;

  const VoiceAudioContent({super.key, required this.themeState});

  /// Audio ducking and push-to-talk both need Windows APIs.
  static final bool _isWindows = !kIsWeb && Platform.isWindows;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppCubit, AppState>(
      builder: (context, appState) {
        // Held to a readable measure. Every row here is a short label over a
        // sentence of explanation, and on a wide window those sentences would
        // otherwise run the full width of the panel.
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              AudioDeviceSection(themeState: themeState),
              _divider(),
              AudioProcessingSection(
                themeState: themeState,
                appState: appState,
              ),
              const SizedBox(height: 20),
              MicTestSection(themeState: themeState),
              _divider(),
              if (_isWindows) ...[
                SectionTitle(label: 'Audio Ducking', themeState: themeState),
                const SizedBox(height: 12),
                SettingToggleRow(
                  themeState: themeState,
                  title: 'Disable automatic volume lowering',
                  description:
                      "Windows lowers other apps' volume when a call is "
                      'active. Enable this to prevent that.',
                  value: appState.disableAudioDucking,
                  onChanged: context.read<AppCubit>().setDisableAudioDucking,
                ),
                _divider(),
                PushToTalkSection(themeState: themeState, appState: appState),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _divider() => Column(
    children: [
      const SizedBox(height: 24),
      Divider(color: themeState.borderPrimary),
      const SizedBox(height: 16),
    ],
  );
}
