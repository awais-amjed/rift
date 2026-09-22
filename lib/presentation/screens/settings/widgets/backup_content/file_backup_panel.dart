import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/vault/vault_cubit.dart';
import '../../../../../logic/helper_methods.dart';
import '../../../../common/app_button.dart';
import '../../../../common/app_modal.dart';
import '../../../../common/button_footer.dart';
import '../../../../common/restore_file_dialog.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import '../section_title.dart';

/// Export the vault to a file, or restore from one. No account involved.
class FileBackupPanel extends StatefulWidget {
  const FileBackupPanel({super.key});

  @override
  State<FileBackupPanel> createState() => _FileBackupPanelState();
}

class _FileBackupPanelState extends State<FileBackupPanel> {
  bool _isExporting = false;

  Future<void> _exportToFile() async {
    setState(() => _isExporting = true);
    try {
      final vaultCubit = context.read<VaultCubit>();
      final export = await vaultCubit.exportBackup();
      if (!export.success || export.content == null) {
        HelperMethods.showError(
          error: export.error ?? 'Failed to export backup',
        );
        return;
      }

      final location = await getSaveLocation(
        suggestedName: 'rift-backup.json',
        acceptedTypeGroups: const [
          XTypeGroup(label: 'Rift backup', extensions: ['json']),
        ],
      );
      if (location == null) return; // user cancelled

      final file = XFile.fromData(
        Uint8List.fromList(utf8.encode(export.content!)),
        mimeType: 'application/json',
      );
      await file.saveTo(location.path);

      HelperMethods.showToast(
        title: 'Backup exported',
        description: 'Encrypted backup saved to ${location.path}',
      );
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  void _restoreFromFile() {
    showCustomDialog(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<VaultCubit>(),
        child: const RestoreFileDialog(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(label: 'Backup file'),
        const SizedBox(height: 4),
        Text(
          'Export your encrypted backup as a file, or restore from one. '
          'Works entirely offline — no account needed.',
          style: AppText.secondary.copyWith(
            color: theme.textTertiary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        ButtonFooter(
          alignment: MainAxisAlignment.start,
          buttons: [
            AppButton(
              label: 'Export',
              isLoading: _isExporting,
              icon: const Icon(Icons.save_alt_rounded, size: 15),
              onPressed: _isExporting ? null : _exportToFile,
            ),
            AppButton(
              label: 'Restore',
              variant: AppButtonVariant.secondary,
              onPressed: _isExporting ? null : _restoreFromFile,
            ),
          ],
        ),
      ],
    );
  }
}
