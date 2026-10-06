import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../../logic/cubits/update/update_cubit.dart';
import '../../../common/app_button.dart';
import '../../../common/setting_row.dart';
import '../../../common/update/restart_to_update.dart';
import 'section_title.dart';
import 'setting_toggle_row.dart';

/// Settings' Updates: which version this is, what the updater is doing, and
/// whether betas come too. Windows and Linux only, where Rift can replace
/// itself.
class UpdatesSection extends StatelessWidget {
  const UpdatesSection({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<UpdateCubit>().state;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(label: 'Updates'),
        const SizedBox(height: 12),
        if (!state.canUpdate)
          const SettingRow(
            title: "This copy can't update itself",
            description:
                'Install Rift from joinrift.app to get each new version as '
                'it comes out.',
            control: SizedBox.shrink(),
          )
        else ...[
          SettingRow(
            title: 'Rift ${state.installedVersion}',
            description: _describe(state),
            control: _action(context, state),
          ),
          const SizedBox(height: 12),
          SettingToggleRow(
            title: 'Get beta updates',
            description: 'Try new features early, before they are finished.',
            value: context.select<AppCubit, bool>(
              (c) => c.state.wantsBetaUpdates(state.installedVersion),
            ),
            onChanged: context.read<AppCubit>().setBetaUpdates,
          ),
        ],
      ],
    );
  }

  static String _describe(UpdateState state) => switch (state.status) {
    UpdateStatus.unsupported || UpdateStatus.upToDate => 'Up to date.',
    UpdateStatus.checking => 'Checking for updates…',
    UpdateStatus.downloading =>
      'Downloading ${state.version}: ${state.progress}%',
    UpdateStatus.ready =>
      '${state.version} is ready. Restart Rift to start using it.',
    UpdateStatus.restarting => 'Restarting…',
    UpdateStatus.failed =>
      "Couldn't get the update. Check your connection and try again.",
  };

  static Widget _action(BuildContext context, UpdateState state) =>
      switch (state.status) {
        UpdateStatus.ready => AppButton(
          label: 'Restart',
          onPressed: () => restartToUpdate(context),
        ),
        UpdateStatus.upToDate || UpdateStatus.failed => AppButton(
          label: 'Check now',
          variant: AppButtonVariant.secondary,
          onPressed: context.read<UpdateCubit>().check,
        ),
        _ => const SizedBox.shrink(),
      };
}
