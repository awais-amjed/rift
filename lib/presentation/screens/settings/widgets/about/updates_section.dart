import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/update/update_cubit.dart';
import '../../../../../logic/services/byte_format.dart';
import '../../../../common/app_button.dart';
import '../../../../common/progress_track.dart';
import '../../../../common/setting_row.dart';
import '../../../../common/update/restart_to_update.dart';
import '../section_title.dart';
import '../setting_toggle_row.dart';

/// Settings' Updates: which version this is, what the updater is doing, and
/// whether betas come too. Windows and Linux only, where Rift can replace
/// itself. A download shows its size and speed, and can be paused, resumed
/// and cancelled.
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
          SettingRow(
            title: "This copy can't update itself",
            description: Platform.isLinux
                ? 'The AppImage from joinrift.app updates itself as each new '
                      'version comes out.'
                : 'Install Rift from joinrift.app to get each new version as '
                      'it comes out.',
            control: const SizedBox.shrink(),
          )
        else ...[
          SettingRow(
            title: 'Rift ${state.installedVersion}',
            description: describe(state),
            control: _action(context, state),
          ),
          if (state.status == UpdateStatus.downloading ||
              state.status == UpdateStatus.paused) ...[
            const SizedBox(height: 10),
            ProgressTrack(progress: state.fraction),
          ],
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

  /// The line under the version: what the updater is doing.
  @visibleForTesting
  static String describe(UpdateState state) => switch (state.status) {
    UpdateStatus.unsupported || UpdateStatus.upToDate => 'Up to date.',
    UpdateStatus.checking => 'Checking for updates…',
    UpdateStatus.available =>
      state.totalBytes > 0
          ? '${state.version} is out (${humanSize(state.totalBytes)}).'
          : '${state.version} is out.',
    UpdateStatus.downloading when state.preparing =>
      'Getting ${state.version} ready…',
    UpdateStatus.downloading =>
      'Downloading ${state.version}: ${_soFar(state)}'
          '${state.bytesPerSecond > 0 ? ' · ${humanSize(state.bytesPerSecond)}/s' : ''}',
    UpdateStatus.paused => 'Paused at ${_soFar(state)}.',
    UpdateStatus.ready =>
      '${state.version} is ready. Restart Rift to start using it.',
    UpdateStatus.restarting => 'Restarting…',
    UpdateStatus.failed =>
      "Couldn't get the update. Check your connection and try again.",
  };

  static String _soFar(UpdateState state) =>
      '${humanSize(state.downloadedBytes)} of ${humanSize(state.totalBytes)}';

  static Widget _action(BuildContext context, UpdateState state) {
    final updates = context.read<UpdateCubit>();
    return switch (state.status) {
      UpdateStatus.ready => AppButton(
        label: 'Restart',
        onPressed: () => restartToUpdate(context),
      ),
      UpdateStatus.available => AppButton(
        label: 'Download',
        onPressed: updates.download,
      ),
      UpdateStatus.downloading when state.preparing => const SizedBox.shrink(),
      UpdateStatus.downloading => _pair(
        AppButton(
          label: 'Pause',
          variant: AppButtonVariant.secondary,
          onPressed: updates.pause,
        ),
        updates,
      ),
      UpdateStatus.paused => _pair(
        AppButton(label: 'Resume', onPressed: updates.resume),
        updates,
      ),
      UpdateStatus.upToDate || UpdateStatus.failed => AppButton(
        label: 'Check now',
        variant: AppButtonVariant.secondary,
        onPressed: updates.checkNow,
      ),
      _ => const SizedBox.shrink(),
    };
  }

  /// [first] beside the download's Cancel.
  static Widget _pair(Widget first, UpdateCubit updates) => Row(
    mainAxisSize: MainAxisSize.min,
    spacing: 8,
    children: [
      first,
      AppButton(
        label: 'Cancel',
        variant: AppButtonVariant.secondary,
        onPressed: updates.cancel,
      ),
    ],
  );
}
