import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/services/host_platform.dart';
import '../section_divider.dart';
import 'call_shortcuts_section.dart';
import 'push_to_talk_section.dart';

/// Settings' Keybinds tab: push-to-talk, and the keys for mute and deafen.
/// Desktop only ([SettingsTab.available]). Push-to-talk is Windows and Linux,
/// so on a Mac the tab holds the call keys alone.
class KeybindsContent extends StatelessWidget {
  const KeybindsContent({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppCubit, AppState>(
      builder: (context, appState) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (HostPlatform.hasPushToTalk) ...[
              PushToTalkSection(appState: appState),
              const SectionDivider(),
            ],
            CallShortcutsSection(shortcuts: appState.callShortcuts),
          ],
        );
      },
    );
  }
}
