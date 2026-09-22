import 'package:flutter/material.dart';

import '../../../../../../data/enums/call_sound.dart';
import '../../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../../logic/services/host_platform.dart';
import '../../section_title.dart';
import 'call_sound_row.dart';

/// The tones a call plays on this device, each pair muted or turned down on
/// its own. Nobody else hears these, so nothing here reaches a server.
class CallSoundsSection extends StatelessWidget {
  final AppState appState;

  const CallSoundsSection({super.key, required this.appState});

  @override
  Widget build(BuildContext context) {
    // Push-to-talk tones only exist where push-to-talk does.
    final sounds = [
      for (final sound in CallSound.values)
        if (sound != CallSound.pushToTalk || HostPlatform.hasPushToTalk) sound,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(label: 'Call sounds'),
        for (final sound in sounds) ...[
          const SizedBox(height: 16),
          CallSoundRow(
            sound: sound,
            setting: sound.settingIn(appState.callSounds),
          ),
        ],
      ],
    );
  }
}
