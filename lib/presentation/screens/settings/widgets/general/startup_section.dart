import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/app/app_cubit.dart';
import '../section_title.dart';
import '../setting_toggle_row.dart';

/// Settings' Startup section: whether the computer starts Rift at sign-in,
/// and whether that start stays in the tray. See `LoginLaunch`.
class StartupSection extends StatelessWidget {
  const StartupSection({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppCubit>();
    final atLogin = context.select<AppCubit, bool>((c) => c.launchesAtLogin);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(label: 'Startup'),
        const SizedBox(height: 12),
        SettingToggleRow(
          title: 'Open Rift when your computer starts',
          description: 'Best for catching calls and messages as they come.',
          value: atLogin,
          onChanged: app.setLaunchAtLogin,
        ),
        const SizedBox(height: 14),
        SettingToggleRow(
          title: 'Start minimized',
          description:
              'Best for keeping Rift out of the way until you need it.',
          value: context.select<AppCubit, bool>((c) => c.state.startMinimized),
          // Only a start at sign-in is minimized; opening Rift by hand
          // always shows it.
          onChanged: atLogin ? app.setStartMinimized : null,
        ),
      ],
    );
  }
}
