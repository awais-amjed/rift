import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/constants.dart';
import '../../../../../data/invite_link.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/vault/vault_cubit.dart';
import '../../../../../logic/helper_methods.dart';
import '../../../../common/app_button.dart';
import '../../../../common/app_modal.dart';
import '../../../../common/app_text_field.dart';
import '../../../../common/message_banner.dart';

/// The join step of [AddServerDialog]: one invite link (server URL and code
/// combined) plus the username and display name to join under.
class JoinServerModal extends StatefulWidget {
  final VoidCallback onSuccess;
  final VoidCallback onCancel;

  const JoinServerModal({
    super.key,
    required this.onSuccess,
    required this.onCancel,
  });

  @override
  State<JoinServerModal> createState() => _JoinServerModalState();
}

class _JoinServerModalState extends State<JoinServerModal> {
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
    return AppModal(
      title: 'Join Server',
      subtitle: 'Join a server with an invite link',
      maxWidth: K.dialogWidth,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: MessageBanner(
                message: _error!,
                kind: MessageBannerKind.error,
              ),
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
        ],
      ),
      // Back first, then the way on — reading order should run from the way
      // out to the commit, not the other way round.
      actions: [
        AppButton(
          label: 'Back',
          variant: AppButtonVariant.secondary,
          onPressed: _isLoading ? null : widget.onCancel,
        ),
        AppButton(
          label: _isLoading ? 'Joining…' : 'Join server',
          onPressed: _canSubmit && !_isLoading ? _submit : null,
          isLoading: _isLoading,
        ),
      ],
    );
  }
}
