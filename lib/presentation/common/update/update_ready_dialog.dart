import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../logic/cubits/update/update_cubit.dart';
import '../../theme/app_text.dart';
import '../../theme/custom_colors.dart';
import '../../theme/theme_context.dart';
import '../app_button.dart';
import '../app_modal.dart';
import '../icon_tile.dart';
import '../message_markup_text.dart';
import 'restart_to_update.dart';

/// The downloaded update's notes, with the restart that starts it.
Future<void> showUpdateReadyDialog(BuildContext context) {
  return showCustomDialog<void>(
    context: context,
    barrierDismissible: true,
    build: (_) => MultiBlocProvider(
      providers: [
        BlocProvider.value(value: context.read<UpdateCubit>()),
        BlocProvider.value(value: context.read<LiveKitCubit>()),
      ],
      child: const _UpdateReadyDialog(),
    ),
  );
}

class _UpdateReadyDialog extends StatelessWidget {
  const _UpdateReadyDialog();

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final state = context.watch<UpdateCubit>().state;
    final notes = state.notes.trim();
    final restarting = state.status == UpdateStatus.restarting;
    return AppModal(
      staysDialogOnPhone: true,
      title: 'Rift ${state.version ?? ''} is ready',
      titleIcon: IconTile.title(
        icon: Icons.system_update_alt_rounded,
        color: CustomColors.success,
      ),
      maxWidth: 480,
      maxHeight: 560,
      content: notes.isEmpty
          ? Text(
              'Restart Rift to start using it.',
              style: AppText.body.copyWith(color: theme.textSecondary),
            )
          // Full width, so the notes start at the left edge rather than
          // centring as a narrow block. The modal scrolls them when long.
          : SizedBox(
              width: double.infinity,
              child: SelectableText.rich(
                messageMarkupSpan(
                  notes,
                  base: AppText.body.copyWith(color: theme.textSecondary),
                  theme: theme,
                ),
              ),
            ),
      actions: [
        AppButton(
          label: 'Later',
          variant: AppButtonVariant.secondary,
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppButton(
          label: restarting ? 'Restarting…' : 'Restart now',
          onPressed: restarting ? null : () => restartToUpdate(context),
        ),
      ],
    );
  }
}
