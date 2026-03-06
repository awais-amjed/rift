import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/helper_methods.dart';
import '../../../../common/app_button.dart';
import '../../../../common/app_text_field.dart';
import '../../../../theme/custom_colors.dart';
import 'create_user_dialog.dart';

/// Form to join an existing server using a Supabase URL and access token.
class JoinServerForm extends StatefulWidget {
  final VoidCallback onSuccess;
  final VoidCallback onCancel;

  const JoinServerForm({
    super.key,
    required this.onSuccess,
    required this.onCancel,
  });

  @override
  State<JoinServerForm> createState() => _JoinServerFormState();
}

class _JoinServerFormState extends State<JoinServerForm> {
  final _supabaseUrlCtrl = TextEditingController();
  final _tokenCtrl = TextEditingController();

  bool _isLoading = false;
  String? _error;

  bool get _canSubmit =>
      _supabaseUrlCtrl.text.trim().isNotEmpty &&
      _tokenCtrl.text.trim().isNotEmpty;

  @override
  void dispose() {
    _supabaseUrlCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final supabaseUrl = _supabaseUrlCtrl.text.trim();
    final token = _tokenCtrl.text.trim();

    // Validate token and check if user exists
    final result = await context.read<ServerCubit>().validateAndJoinServer(
      supabaseUrl,
      token,
    );

    if (!mounted) return;

    setState(() => _isLoading = false);

    if (!result.success) {
      setState(() => _error = result.error);
      return;
    }

    if (result.userExists) {
      // User already exists, server was added by cubit
      HelperMethods.showSuccess(message: 'Joined server successfully!');
      widget.onSuccess();
    } else {
      // User doesn't exist, show create user dialog
      _showCreateUserDialog();
    }
  }

  void _showCreateUserDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => BlocProvider.value(
        value: context.read<ServerCubit>(),
        child: const CreateUserDialog(),
      ),
    ).then((created) {
      if (created == true) {
        HelperMethods.showSuccess(message: 'Joined server successfully!');
        widget.onSuccess();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_error != null) _ErrorBanner(message: _error!),
        AppTextField(
          controller: _supabaseUrlCtrl,
          label: 'Supabase URL',
          hint: 'https://xxxxx.supabase.co',
          enabled: !_isLoading,
          autofocus: true,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 14),
        AppTextField(
          controller: _tokenCtrl,
          label: 'Access Token',
          hint: 'Enter your access token',
          enabled: !_isLoading,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: AppButton(
                label: _isLoading ? 'Connecting...' : 'Continue',
                onPressed: _canSubmit && !_isLoading ? _submit : null,
                isLoading: _isLoading,
                expanded: true,
              ),
            ),
            const SizedBox(width: 10),
            AppButton(
              label: 'Back',
              variant: AppButtonVariant.secondary,
              onPressed: _isLoading ? null : widget.onCancel,
            ),
          ],
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: CustomColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CustomColors.error.withValues(alpha: 0.3)),
      ),
      child: Text(
        message,
        style: const TextStyle(fontSize: 13, color: CustomColors.error),
      ),
    );
  }
}
