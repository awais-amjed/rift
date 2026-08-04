import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import 'widgets/auth_view.dart';
import 'widgets/signed_in_view.dart';
import '../../../../theme/app_text.dart';

/// Full-screen view for managing Supabase cloud backups.
///
/// Flow:
///   • Not signed in → [AuthView] (sign-up / sign-in)
///   • Signed in     → [SignedInView] (save / import backup)
class SupabaseBackupScreen extends StatelessWidget {
  const SupabaseBackupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Uses the app-global SupabaseBackupCubit provided in main.dart.
    return const _SupabaseBackupView();
  }
}

class _SupabaseBackupView extends StatelessWidget {
  const _SupabaseBackupView();

  @override
  Widget build(BuildContext context) {
    final theme = context.read<ThemeCubit>().state;

    return Scaffold(
      backgroundColor: theme.bgPrimary,
      appBar: AppBar(
        backgroundColor: theme.bgSecondary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Cloud Backup',
          style: AppText.row.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: theme.textPrimary,
          ),
        ),
        leading: BackButton(color: theme.textSecondary),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: theme.borderPrimary),
        ),
      ),
      body: BlocBuilder<SupabaseBackupCubit, SupabaseBackupState>(
        builder: (context, state) {
          return SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 24,
                  ),
                  child: state.isSignedIn
                      ? SignedInView(state: state)
                      : AuthView(state: state),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
