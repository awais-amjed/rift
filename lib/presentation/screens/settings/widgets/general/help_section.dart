import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/repositories/bug_report_repository.dart';
import '../../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../../../../logic/helper_methods.dart';
import '../../../../../logic/services/app_log.dart';
import '../../../../../logic/services/host_platform.dart';
import '../../../../../logic/services/open_link.dart';
import '../../../../common/app_button.dart';
import '../../../../common/setting_row.dart';
import '../../../../common/show_custom_dialog.dart';
import '../section_title.dart';
import 'bug_report_dialog.dart';

/// Settings' Help: sending a bug report, and on a desktop, the logs folder
/// for someone sending them by hand.
class HelpSection extends StatelessWidget {
  const HelpSection({super.key});

  @override
  Widget build(BuildContext context) {
    final logs = AppLog.directory;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(label: 'Help'),
        const SizedBox(height: 12),
        SettingRow(
          title: 'Report a bug',
          description: 'For when something went wrong. Your logs go with it.',
          control: AppButton(
            label: 'Report…',
            variant: AppButtonVariant.secondary,
            onPressed: () => _report(context),
          ),
        ),
        if (HostPlatform.isDesktop && logs != null) ...[
          const SizedBox(height: 12),
          SettingRow(
            title: 'Logs',
            description: 'Kept on this device, for the last ten sessions.',
            control: AppButton(
              label: 'Open folder',
              variant: AppButtonVariant.secondary,
              onPressed: () async {
                if (!await openOwnFolder(logs.path)) {
                  HelperMethods.showError(error: 'Could not open ${logs.path}');
                }
              },
            ),
          ),
        ],
      ],
    );
  }

  void _report(BuildContext context) {
    final signedIn = context.read<SupabaseBackupCubit>().state.isSignedIn;
    final repository = BugReportRepository();
    showCustomDialog<void>(
      context: context,
      build: (_) =>
          BugReportDialog(signedIn: signedIn, onSend: repository.send),
    );
  }
}
