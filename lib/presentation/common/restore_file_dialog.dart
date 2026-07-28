import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../logic/cubits/vault/vault_cubit.dart';
import '../../logic/helper_methods.dart';
import 'app_button.dart';
import 'app_modal.dart';
import 'app_text_field.dart';
import 'message_banner.dart';

/// Dialog for restoring a vault from an exported backup file.
///
/// Fully offline — used from the privacy-mode onboarding path and settings.
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
      setState(() => _error = 'Enter the vault password');
      return;
    }

    setState(() {
      _isProcessing = true;
      _error = null;
    });

    try {
      final content = await file.readAsString();
      final result = await context.read<VaultCubit>().importBackup(
        jsonContent: content,
        password: _passwordController.text,
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
            label: 'Vault Password',
            hint: 'Password used when the backup was created',
            obscureText: true,
            enabled: !_isProcessing,
            onEditingComplete: _isProcessing ? null : _restore,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            MessageBanner(message: _error!, isError: true),
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
