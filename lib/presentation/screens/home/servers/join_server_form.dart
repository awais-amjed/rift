import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/invite_link.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/vault/vault_cubit.dart';
import '../../../../../logic/helper_methods.dart';
import '../../../common/app_button.dart';
import '../../../common/app_text_field.dart';
import '../../../common/message_banner.dart';

/// Form to join an existing server using a single invite link (server URL +
/// invite code combined) plus a username / display name.
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
  final _inviteLinkCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _displayNameCtrl = TextEditingController();

  bool _isLoading = false;
  String? _error;

  bool get _canSubmit =>
      _inviteLinkCtrl.text.trim().isNotEmpty &&
      _usernameCtrl.text.trim().isNotEmpty &&
      _displayNameCtrl.text.trim().isNotEmpty;

  @override
  void dispose() {
    _inviteLinkCtrl.dispose();
    _usernameCtrl.dispose();
    _displayNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;

    final link = InviteLink.parse(_inviteLinkCtrl.text);
    if (link == null) {
      setState(() {
        _error =
            "That doesn't look like a complete invite link. Ask the "
            'server admin for a new one.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final supabaseUrl = link.serverUrl;
    final inviteCode = link.inviteCode;
    final username = _usernameCtrl.text.trim();
    final displayName = _displayNameCtrl.text.trim();

    // Register using cryptographic identity
    final result = await context.read<VaultCubit>().registerOnServer(
      supabaseUrl: supabaseUrl,
      inviteCode: inviteCode,
      username: username,
      displayName: displayName,
    );

    if (!mounted) return;

    if (!result.success) {
      setState(() {
        _error = result.error;
        _isLoading = false;
      });
      return;
    }

    // register now returns full server context — add directly
    final data = result.data!;
    final token = data['token'] as String;
    final serverCubit = context.read<ServerCubit>();
    serverCubit.addServer(supabaseUrl, token, data);

    if (!mounted) return;

    setState(() => _isLoading = false);

    HelperMethods.showSuccess(message: 'Joined server successfully!');
    widget.onSuccess();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: MessageBanner(message: _error!, isError: true),
          ),

        AppTextField(
          controller: _inviteLinkCtrl,
          label: 'Invite Link',
          hint: 'Paste the invite link you received',
          enabled: !_isLoading,
          autofocus: true,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),

        AppTextField(
          controller: _usernameCtrl,
          label: 'Username',
          hint: 'myusername',
          enabled: !_isLoading,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        AppTextField(
          controller: _displayNameCtrl,
          label: 'Display Name',
          hint: 'How others will see you',
          enabled: !_isLoading,
          onChanged: (_) => setState(() {}),
        ),

        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: AppButton(
                label: _isLoading ? 'Joining...' : 'Join Server',
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
