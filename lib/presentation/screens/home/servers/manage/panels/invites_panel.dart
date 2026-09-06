import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/classes/server.dart';
import '../../../../../../data/invite_link.dart';
import '../../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../../data/classes/role.dart';
import '../../../../../../data/enums/server_permission.dart';
import '../../../../../../logic/services/role_ladder.dart';
import '../../../../../common/app_button.dart';
import '../../../invites/invite_summary.dart';
import '../../../invites/widgets/invite_form.dart';
import '../../../invites/widgets/invite_options.dart';
import '../widgets/manage_panel.dart';

part 'invites_panel_roles.dart';

/// The invites page of the manage-server dialog: mint a link for [server]
/// and copy it.
///
/// Takes the server rather than reading the selection: the dialog opens from
/// the rail's menu, which can be a server you are not currently looking at.
class InvitesPanel extends StatefulWidget {
  final Server server;

  const InvitesPanel({super.key, required this.server});

  @override
  State<InvitesPanel> createState() => _InvitesPanelState();
}

class _InvitesPanelState extends State<InvitesPanel> with _InviteRolesMixin {
  bool _isGenerating = false;
  String? _inviteToken;
  String? _error;
  bool _copiedLink = false;

  // Expiry — default: 7 days (index 2)
  int _expiryIndex = 2;

  // Max uses — default: 1 (index 0)
  int _usesIndex = 0;

  /// Whether the link being minted makes a bot. Off by default: the common
  /// case is inviting a person, and a bot invite is the deliberate one.
  bool _isBot = false;

  @override
  void initState() {
    super.initState();
    loadRoles();
  }

  void _resetToken() {
    _inviteToken = null;
    _copiedLink = false;
    _error = null;
  }

  Future<void> _generate() async {
    setState(() {
      _isGenerating = true;
      _error = null;
      _inviteToken = null;
    });

    final result = await context.read<ServerCubit>().createInvite(
      maxUses: inviteUsesOptions[_usesIndex].value,
      expiresInSeconds: inviteExpiryOptions[_expiryIndex].seconds,
      serverId: widget.server.id,
      isBot: _isBot,
      roleId: roleId,
    );

    if (!mounted) return;

    setState(() {
      _isGenerating = false;
      if (result.success) {
        _inviteToken = result.inviteCode;
      } else {
        _error = result.error;
      }
    });
  }

  void _copyToClipboard(String text, void Function(bool) setCopied) async {
    await Clipboard.setData(ClipboardData(text: text));
    setCopied(true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setCopied(false);
  }

  @override
  Widget build(BuildContext context) {
    final inviteLink = _inviteToken == null
        ? null
        : InviteLink.build(widget.server.supabaseUrl, _inviteToken!);

    return ManagePanel(
      title: 'Invites',
      subtitle: InviteSummary.of(
        expiryIndex: _expiryIndex,
        usesIndex: _usesIndex,
        role: selectedRole,
      ),
      footer: [
        AppButton(
          label: _isGenerating
              ? 'Generating...'
              : _inviteToken != null
              ? 'Regenerate'
              : 'Generate',
          isLoading: _isGenerating,
          onPressed: _isGenerating ? null : _generate,
          icon: _isGenerating
              ? null
              : const Icon(
                  Icons.person_add_outlined,
                  size: 15,
                  color: Colors.white,
                ),
        ),
      ],
      child: InviteForm(
        expiryIndex: _expiryIndex,
        usesIndex: _usesIndex,
        onExpirySelected: (i) => setState(() {
          _expiryIndex = i;
          _resetToken();
        }),
        onUsesSelected: (i) => setState(() {
          _usesIndex = i;
          _resetToken();
        }),
        roles: roles,
        roleId: roleId,
        onRoleSelected: (id) => setState(() {
          roleId = id;
          // A link already on screen was minted with the other role, so it
          // no longer matches what the picker says.
          _resetToken();
        }),
        isBot: _isBot,
        onIsBotChanged: (value) => setState(() {
          _isBot = value;
          // A link already on screen was minted as the other kind, so it
          // no longer matches what the switch says.
          _resetToken();
        }),
        inviteLink: inviteLink,
        isGenerating: _isGenerating,
        copied: _copiedLink,
        onCopy: inviteLink == null
            ? null
            : () => _copyToClipboard(
                inviteLink,
                (v) => setState(() => _copiedLink = v),
              ),
        error: _error,
      ),
    );
  }
}
