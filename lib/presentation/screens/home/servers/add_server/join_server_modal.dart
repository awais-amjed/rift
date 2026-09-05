import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/public_server.dart';
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
///
/// Also the last step of the browser. A listing is an address and an invite
/// code, which is exactly what a link is — so arriving from the directory
/// fills in [listing] and this becomes the same form with one fewer field,
/// rather than a second registration path that could drift from this one.
class JoinServerModal extends StatefulWidget {
  /// Called once the join has landed.
  ///
  /// [joinedAsAdmin] is what lets the flow ask an admin the questions the
  /// create flow asks — description, tags, whether to list it. Somebody whose
  /// server was made for them by the self-hosted console joins their own
  /// server rather than creating it, and was never offered any of them.
  final void Function({required bool joinedAsAdmin}) onSuccess;
  final VoidCallback onCancel;

  /// The server picked in the browser, or null when the link is typed.
  final PublicServer? listing;

  /// An invite that arrived from outside the app — a tapped link. Same
  /// standing as a listing: something already chosen, so the field goes away.
  final String? inviteLink;

  const JoinServerModal({
    super.key,
    required this.onSuccess,
    required this.onCancel,
    this.listing,
    this.inviteLink,
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

  /// The listing's link, when we arrived from the browser. Held rather than
  /// put in the field: it is not something to edit, and showing an invite code
  /// in a box invites someone to try.
  String? get _prefilled => widget.inviteLink ?? widget.listing?.inviteLink;

  /// The host the invite points at.
  ///
  /// The one line of provenance someone should see before handing over a
  /// username: a listing names itself, and a tapped link has to be read for
  /// it. Null when the link is still to be typed — there is nothing to say yet.
  String? get _host {
    final listing = widget.listing;
    if (listing != null) return listing.host;

    final link = widget.inviteLink;
    if (link == null) return null;
    final parsed = InviteLink.parse(link);
    if (parsed == null) return null;
    return Uri.tryParse(parsed.serverUrl)?.host ?? parsed.serverUrl;
  }

  bool get _canSubmit =>
      (_prefilled != null || _inviteLinkCtrl.text.trim().isNotEmpty) &&
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

    final link = InviteLink.parse(_prefilled ?? _inviteLinkCtrl.text);
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

    // Read off the register response rather than the roster, which has not
    // been fetched yet at this point.
    final permissions =
        (data['user'] as Map?)?['permissions'] as Map<String, dynamic>?;
    widget.onSuccess(joinedAsAdmin: permissions?['is_server_admin'] == true);
  }

  @override
  Widget build(BuildContext context) {
    final listing = widget.listing;
    // Chosen already — from the browser, or by tapping an invite. Either way
    // the link is not something to ask for or to edit.
    final chosen = _prefilled != null;

    return AppModal(
      title: listing == null ? 'Join Server' : 'Join ${listing.name}',
      subtitle: chosen
          ? 'Pick how you will appear on ${_host ?? 'this server'}'
          : 'Join a server with an invite link',
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

          if (!chosen) ...[
            AppTextField(
              controller: _inviteLinkCtrl,
              label: 'Invite Link',
              hint: 'Paste the invite link you received',
              enabled: !_isLoading,
              autofocus: true,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
          ],

          AppTextField(
            controller: _usernameCtrl,
            label: 'Username',
            hint: 'myusername',
            enabled: !_isLoading,
            autofocus: chosen,
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
