import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../../data/apis/invites_api.dart';
import '../../../../../../data/classes/server_invite.dart';
import '../../../../../../logic/cubits/server_members/server_members_cubit.dart';
import '../../../../../common/app_button.dart';
import '../../../../../common/confirm_dialog.dart';
import '../../../../../common/hint_card.dart';
import '../../../../../common/loading_block.dart';
import '../../../../../common/message_banner.dart';
import '../../../../../common/server_scope.dart';
import '../widgets/manage_panel.dart';
import 'invites/invite_list_row.dart';

/// The Invites page of the manage-server dialog: every link into the server
/// that still works, and revoking one.
///
/// Without it a link could only run out. One posted where it should not have
/// been, or left behind by a member since kicked, kept letting people in, and
/// making a new link in the invite dialog left the old one working too.
/// Read when the page opens and thrown away when it closes, as the webhook
/// list is: nothing else on screen draws these.
class InvitesPanel extends StatefulWidget {
  const InvitesPanel({super.key});

  @override
  State<InvitesPanel> createState() => _InvitesPanelState();
}

class _InvitesPanelState extends State<InvitesPanel> {
  late final InvitesApi _api;

  /// Null while the first read is out.
  List<ServerInvite>? _invites;
  bool _failed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _api = InvitesApi(ServerScope.read(context));
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    final invites = await _api.listInvites();
    if (!mounted) return;
    setState(() {
      if (invites == null) {
        _failed = true;
      } else {
        _invites = invites;
      }
    });
  }

  Future<void> _revoke(ServerInvite invite) async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Revoke this link?',
      message:
          'Nobody can join with it from now on. People who already joined '
          'with it stay.',
      confirmLabel: 'Revoke',
      icon: Icons.link_off_rounded,
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;
    final result = await _api.revoke(invite.id);
    if (!mounted) return;
    setState(() => _error = result.error);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    // `@everyone` left out: a link naming it hands out nothing more than
    // joining does, so it reads as a plain link.
    final roles = {
      for (final role in context.select(
        (ServerMembersCubit c) => c.state.roles,
      ))
        if (!role.isEveryone) role.id: role.name,
    };
    final invites = _invites;
    final now = DateTime.now();
    final live = [
      for (final invite in invites ?? const <ServerInvite>[])
        if (!invite.expiredAt(now)) invite,
    ];

    return ManagePanel(
      title: 'Invites',
      subtitle: 'Links that can still be used to join',
      error: _error,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          if (invites == null && _failed)
            MessageBanner(
              message: "Couldn't read the links to this server.",
              kind: MessageBannerKind.error,
              action: AppButton(
                label: 'Try again',
                variant: AppButtonVariant.secondary,
                onPressed: () => unawaited(_load()),
              ),
            )
          else if (invites == null)
            const LoadingBlock(height: 120)
          else if (live.isEmpty)
            const HintCard(
              icon: Icons.link_off_rounded,
              text: 'No links right now. Make one from Invite people.',
            )
          else
            for (final invite in live)
              InviteListRow(
                key: ValueKey(invite.id),
                invite: invite,
                now: now,
                roleName: invite.roleId == null ? null : roles[invite.roleId],
                onRevoke: () => unawaited(_revoke(invite)),
              ),
        ],
      ),
    );
  }
}
