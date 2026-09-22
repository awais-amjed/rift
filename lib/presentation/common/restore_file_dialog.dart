import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../logic/cubits/vault/vault_cubit.dart';
import '../../logic/helper_methods.dart';
import '../theme/app_text.dart';
import '../theme/theme_context.dart';
import 'app_button.dart';
import 'app_modal.dart';
import 'app_text_field.dart';
import 'message_banner.dart';

/// Dialog for restoring a vault from an exported backup file.
///
/// Fully offline — used from the privacy-mode onboarding path and settings.
///
/// Takes either the password or the recovery key, as a choice rather than a
/// fallback. The two unwrap independent blobs holding the same seed, so trying
/// one and then the other would mean reporting whichever failed last as the
/// reason — telling somebody their recovery key is wrong when what they typed
/// was a password.
class RestoreFileDialog extends StatefulWidget {
  const RestoreFileDialog({super.key});

  @override
  State<RestoreFileDialog> createState() => _RestoreFileDialogState();
}

class _RestoreFileDialogState extends State<RestoreFileDialog> {
  final _passwordController = TextEditingController();
  XFile? _file;
  String? _error;
  bool _isProcessing = false;
  bool _useRecoveryKey = false;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Rift backup', extensions: ['json']),
      ],
    );
    if (file != null) {
      setState(() {
        _file = file;
        _error = null;
      });
    }
  }

  Future<void> _restore() async {
    final file = _file;
    if (file == null) {
      setState(() => _error = 'Choose a backup file first');
      return;
    }
    if (_passwordController.text.isEmpty) {
      setState(
        () => _error = _useRecoveryKey
            ? 'Enter your recovery key'
            : 'Enter the vault password',
      );
      return;
    }

    setState(() {
      _isProcessing = true;
      _error = null;
    });

    try {
      final vault = context.read<VaultCubit>();
      final content = await file.readAsString();
      final result = await vault.importBackup(
        jsonContent: content,
        password: _useRecoveryKey ? null : _passwordController.text,
        recoveryKey: _useRecoveryKey ? _passwordController.text : null,
      );

      if (!mounted) return;
      if (result.success) {
        Navigator.of(context).pop();
        HelperMethods.showToast(
          title: 'Vault restored',
          description: 'Your identity was imported from the backup file.',
        );
      } else {
        setState(() {
          _isProcessing = false;
          _error = result.error ?? 'Failed to restore backup';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _error = 'Could not read file: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppModal(
      title: 'Restore from File',
      subtitle: 'Import a previously exported backup file.',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          AppButton(
            label: _file == null ? 'Choose backup file…' : _file!.name,
            variant: AppButtonVariant.secondary,
            icon: const Icon(Icons.file_open_rounded, size: 18),
            onPressed: _isProcessing ? null : _pickFile,
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: _passwordController,
            label: _useRecoveryKey ? 'Recovery key' : 'Vault password',
            hint: _useRecoveryKey
                ? 'XXXXX-XXXXX-XXXXX-XXXXX-XXXXX'
                : 'Password used when the backup was created',
            // A recovery key is read off paper and typed once. Hiding it
            // behind dots turns the one input people cannot retype from
            // memory into the one they cannot check either.
            obscureText: !_useRecoveryKey,
            enabled: !_isProcessing,
            onEditingComplete: _isProcessing ? null : _restore,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _isProcessing
                  ? null
                  : () => setState(() {
                      _useRecoveryKey = !_useRecoveryKey;
                      _passwordController.clear();
                      _error = null;
                    }),
              child: Text(
                _useRecoveryKey
                    ? 'Use the password instead'
                    : 'Forgotten the password? Use a recovery key',
                style: AppText.secondary.copyWith(color: context.theme.primary),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            MessageBanner(message: _error!, kind: MessageBannerKind.error),
          ],
        ],
      ),
      actions: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.secondary,
          onPressed: _isProcessing ? null : () => Navigator.of(context).pop(),
        ),
        AppButton(
          label: 'Restore',
          isLoading: _isProcessing,
          onPressed: _isProcessing ? null : _restore,
        ),
      ],
    );
  }
}
