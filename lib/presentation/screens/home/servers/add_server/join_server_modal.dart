import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/resolved_invite.dart';
import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/central_dm/central_dm_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/vault/vault_cubit.dart';
import '../../../../../logic/helper_methods.dart';
import '../../../../../logic/services/join_defaults.dart';
import '../../../../../logic/services/server_username.dart';
import '../../../../common/app_button.dart';
import '../../../../common/app_modal.dart';
import '../../../../common/app_text_field.dart';
import '../../../../common/message_banner.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';

/// The second join step: how you will appear on a server that has already
/// answered to its invite.
///
/// Takes a [ResolvedInvite] rather than a link, so there is nothing here to
/// validate but two names — and both start filled in where they can be: the
/// username from the central handle, the display name from the last server
/// joined ([JoinDefaults]). Someone on their fifth server should be pressing
/// one button, not retyping who they are.
///
/// Also the last step of the browser. A listing is an address and an invite
/// code, which is exactly what a resolved invite holds — so arriving from the
/// directory lands here directly rather than on a second registration path.
class JoinServerModal extends StatefulWidget {
  final ResolvedInvite invite;

  /// Called once the join has landed.
  ///
  /// [joinedAsAdmin] is what lets the flow ask an admin the questions the
  /// create flow asks — description, tags, whether to list it. Somebody whose
  /// server was made for them by the self-hosted console joins their own
  /// server rather than creating it, and was never offered any of them.
  final void Function({required bool joinedAsAdmin}) onSuccess;
  final VoidCallback onCancel;

  const JoinServerModal({
    super.key,
    required this.invite,
    required this.onSuccess,
    required this.onCancel,
  });

  @override
  State<JoinServerModal> createState() => _JoinServerModalState();
}

class _JoinServerModalState extends State<JoinServerModal> {
  final _usernameCtrl = TextEditingController();
  final _displayNameCtrl = TextEditingController();

  bool _isLoading = false;
  String? _error;

  bool get _canSubmit =>
      ServerUsername.isValid(_usernameCtrl.text) &&
      _displayNameCtrl.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    final defaults = JoinDefaults.of(
      centralHandle: context.read<CentralDmCubit>().state.myHandle,
      servers: context.read<ServerCubit>().state.servers,
    );
    _usernameCtrl.text = defaults.username;
    _displayNameCtrl.text = defaults.displayName;
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _displayNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final invite = widget.invite;
    final result = await context.read<VaultCubit>().registerOnServer(
      supabaseUrl: invite.serverUrl,
      inviteCode: invite.inviteCode,
      username: _usernameCtrl.text.trim(),
      displayName: _displayNameCtrl.text.trim(),
    );
    if (!mounted) return;

    if (!result.success) {
      setState(() {
        _error = result.error;
        _isLoading = false;
      });
      return;
    }

    // register returns the full server context — add directly.
    final data = result.data!;
    final token = data['token'] as String;
    context.read<ServerCubit>().addServer(invite.serverUrl, token, data);
    if (!mounted) return;

    setState(() => _isLoading = false);
    // Somebody who left and came back is still the member they were — the
    // server kept the row, and the names typed above were not applied — so
    // say which account they are in as rather than let the old name surprise
    // them.
    final rejoinedAs = data['rejoined'] == true
        ? ((data['user'] as Map?)?['display_name'] as String?)
        : null;
    HelperMethods.showSuccess(
      message: rejoinedAs == null
          ? 'Joined ${invite.serverName}'
          : 'Welcome back to ${invite.serverName} — you are $rejoinedAs again',
    );

    // Read off the register response rather than the roster, which has not
    // been fetched yet at this point.
    final permissions =
        (data['user'] as Map?)?['permissions'] as Map<String, dynamic>?;
    widget.onSuccess(joinedAsAdmin: permissions?['is_server_admin'] == true);
  }

  @override
  Widget build(BuildContext context) {
    final invite = widget.invite;
    return AppModal(
      pageOnPhone: true,
      onBack: _isLoading ? null : widget.onCancel,
      title: 'Join ${invite.serverName}',
      subtitle: 'Pick how you will appear on ${invite.host}',
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
            controller: _usernameCtrl,
            label: 'Username',
            hint: 'myusername',
            enabled: !_isLoading,
            autofocus: _usernameCtrl.text.isEmpty,
            // Anything the mention parser cannot express is refused at the
            // keystroke: a username with a space in it is a member nobody can
            // ever @-mention. See [ServerUsername].
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_.-]')),
            ],
            maxLength: ServerUsername.maxLength,
            // A refusal describes what was submitted, not what is being typed
            // now — "that username is taken" has to go once it is a different
            // username.
            onChanged: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: 6),
          Text(
            ServerUsername.rule,
            style: AppText.label.copyWith(color: context.theme.textTertiary),
          ),
          const SizedBox(height: 12),
          AppTextField(
            controller: _displayNameCtrl,
            label: 'Display name',
            hint: 'How others will see you',
            enabled: !_isLoading,
            autofocus: _usernameCtrl.text.isNotEmpty,
            onChanged: (_) => setState(() => _error = null),
            onEditingComplete: _canSubmit && !_isLoading ? _submit : null,
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
