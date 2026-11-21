import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../logic/cubits/app/app_cubit.dart';
import '../section_divider.dart';
import 'clip_shortcut_section.dart';
import 'clipping_section.dart';
import 'recent_clips_section.dart';

/// Settings' Clips tab: the switch and what a clip holds, the clip shortcut,
/// and the clips kept on this device. Windows and Linux only
/// ([SettingsTab.available], [HostPlatform.clipsCalls]).
class ClipsContent extends StatelessWidget {
  const ClipsContent({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppCubit, AppState>(
      builder: (context, appState) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClippingSection(appState: appState),
          const SectionDivider(),
          ClipShortcutSection(appState: appState),
          const SectionDivider(),
          const RecentClipsSection(),
        ],
      ),
    );
  }
}
