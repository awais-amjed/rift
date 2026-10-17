import 'package:flutter/material.dart';

import '../../../../common/app_button.dart';
import '../../../../common/app_modal.dart';
import '../../../../common/app_text_field.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';

/// Deletes the account with the password it was proved by; answers what
/// central said.
typedef AccountDeleter =
    Future<({bool success, String? error})> Function(String password);

/// Delete the Rift account, after typing its password.
///
/// Says what goes and what stays before the button, because the one thing
/// people get wrong about it is the second half: their servers are not the
/// account's, and stay.
class DeleteAccountDialog extends StatefulWidget {
  final String email;
  final AccountDeleter onDelete;

  const DeleteAccountDialog({
    super.key,
    required this.email,
    required this.onDelete,
  });

  @override
  State<DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<DeleteAccountDialog> {
  final _password = TextEditingController();
  bool _deleting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _password.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  bool get _ready => !_deleting && _password.text.isNotEmpty;

  Future<void> _delete() async {
    if (!_ready) return;
    setState(() {
      _deleting = true;
      _error = null;
    });
    final result = await widget.onDelete(_password.text);
    if (!mounted) return;
    if (!result.success) {
      setState(() {
        _deleting = false;
        _error = result.error ?? "Couldn't delete the account.";
      });
      return;
    }
    // The cubit's notice says it is done.
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final body = AppText.secondary.copyWith(color: theme.textSecondary);
    return AppModal(
      title: 'Delete your Rift account?',
      subtitle: widget.email,
      error: _error,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This deletes your account for good: your username, your cloud '
            'backup, your Rift DMs, your friends and your directory listings. '
            'It cannot be undone.',
            style: body,
          ),
          const SizedBox(height: 8),
          Text(
            'Your servers are not part of your account. You stay in them, and '
            'they stay on this device.',
            style: body,
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: _password,
            label: 'Password',
            obscureText: true,
            autofocus: true,
            enabled: !_deleting,
            onSubmitted: (_) => _delete(),
          ),
        ],
      ),
      actions: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.secondary,
          onPressed: _deleting ? null : () => Navigator.of(context).pop(),
        ),
        AppButton(
          label: 'Delete account',
          variant: AppButtonVariant.danger,
          isLoading: _deleting,
          onPressed: _ready ? _delete : null,
        ),
      ],
    );
  }
}
