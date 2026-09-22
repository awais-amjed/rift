import 'package:flutter/material.dart';

import '../../../../../../data/enums/app_sound.dart';
import '../../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../../logic/services/host_platform.dart';
import '../../section_title.dart';
import 'sound_row.dart';

/// The sounds Rift plays on this device — a new message, and the call's
/// cues — each muted or turned down on its own. Nobody else hears these, so nothing here reaches a server.
class SoundsSection extends StatelessWidget {
  final AppState appState;

  const SoundsSection({super.key, required this.appState});

  @override
  Widget build(BuildContext context) {
    // Push-to-talk tones only exist where push-to-talk does.
    final sounds = [
      for (final sound in AppSound.values)
        if (sound != AppSound.pushToTalk || HostPlatform.hasPushToTalk) sound,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(label: 'Sounds'),
        for (final sound in sounds) ...[
          const SizedBox(height: 16),
          SoundRow(sound: sound, setting: sound.settingIn(appState.appSounds)),
        ],
      ],
    );
  }
}
