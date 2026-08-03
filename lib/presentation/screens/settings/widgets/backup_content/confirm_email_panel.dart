import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/app_button.dart';

import '../section_title.dart';

class ConfirmEmailPanel extends StatelessWidget {
  final ThemeState themeState;
  final String? email;

  const ConfirmEmailPanel({super.key, required this.themeState, this.email});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SupabaseBackupCubit>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(label: 'Check Your Email', themeState: themeState),
        const SizedBox(height: 4),
        Text(
          email != null
              ? 'A confirmation link was sent to $email. Click the link, then sign in.'
              : 'A confirmation link was sent to your email. Click the link, then sign in.',
          style: TextStyle(
            fontSize: 12,
            color: themeState.textTertiary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 16),
        AppButton(
          label: 'Sign In After Confirming',
          onPressed: cubit.clearMessage,
        ),
      ],
    );
  }
}
