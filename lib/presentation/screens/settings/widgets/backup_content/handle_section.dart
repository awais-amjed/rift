import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/central_dm/central_dm_cubit.dart';
import '../../../../common/app_button.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import '../../../home/dms/widgets/change_handle_dialog.dart';
import '../section_title.dart';

/// The account's handle, and a button to change it.
///
/// A desktop also changes it from the line under Home's title. On a phone
/// that line is in the bar whose tap opens the switcher, and a second, tiny
/// target inside it was hard to hit and easy to hit by mistake, so there the
/// line only says who you are and the change is made here, with the account.
/// Nothing until a handle is claimed: claiming the first one is Home's job.
class HandleSection extends StatelessWidget {
  const HandleSection({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final handle = context.select<CentralDmCubit, String?>(
      (c) => c.state.myHandle,
    );
    if (handle == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(label: 'Handle'),
        const SizedBox(height: 4),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'People add you on Rift as '),
              TextSpan(
                text: '@$handle',
                // Mono: a handle is an identifier, and it reads as one.
                style: AppText.figure.copyWith(color: theme.textSecondary),
              ),
              const TextSpan(text: '.'),
            ],
          ),
          style: AppText.secondary.copyWith(
            color: theme.textTertiary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        AppButton(
          label: 'Change handle',
          variant: AppButtonVariant.secondary,
          icon: const Icon(Icons.edit_outlined),
          onPressed: () => showChangeHandle(context, handle),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}
