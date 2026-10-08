import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/apis/ownership_api.dart';
import '../../../../../../data/classes/server.dart';
import '../../../../../../data/repositories/session_repository.dart';
import '../../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../../logic/helper_methods.dart';
import '../../../../../common/app_button.dart';
import '../../../../../common/confirm_dialog.dart';
import '../../../../../common/hint_card.dart';
import '../widgets/danger_row.dart';
import '../widgets/manage_panel.dart';

/// The last page, and the owner's alone: ending the server.
///
/// Leaving is not here. It is a member's own business and lives on the rail
/// menu where it always did; this page is the one action that reaches
/// everybody else, so it stands by itself and asks in those words.
class DangerZonePanel extends StatefulWidget {
  final Server server;

  const DangerZonePanel({super.key, required this.server});

  @override
  State<DangerZonePanel> createState() => _DangerZonePanelState();
}

class _DangerZonePanelState extends State<DangerZonePanel> {
  bool _isBusy = false;

  Future<void> _delete() async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Delete ${widget.server.name}?',
      message:
          'Every channel, message and member goes with it, for everybody, '
          'and nothing can bring it back. If you only want to stop running '
          'it yourself, hand it to somebody else instead: open Members, '
          'expand them, and choose Transfer ownership.',
      confirmLabel: 'Delete server',
      icon: Icons.delete_forever_rounded,
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() => _isBusy = true);
    final servers = context.read<ServerCubit>();
    final result = await OwnershipApi(
      session: context.read<SessionRepository>(),
    ).deleteServer(serverId: widget.server.id);
    if (!result.success) {
      if (!mounted) return;
      setState(() => _isBusy = false);
      HelperMethods.showError(error: result.error ?? 'Could not delete');
      return;
    }
    // Forgotten here only once the server has said yes, and whether or not
    // this page is still open to hear it.
    servers.removeServer(widget.server.id);
    if (!mounted) return;
    setState(() => _isBusy = false);
    HelperMethods.showSuccess(message: '${widget.server.name} is gone');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return ManagePanel(
      title: 'Danger zone',
      subtitle: 'Ending this server, for everybody',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: 12,
        children: [
          const HintCard(
            icon: Icons.workspace_premium_outlined,
            text:
                'You own this server. To step down without ending it, hand '
                'it to another member from the Members page.',
          ),
          DangerRow(
            icon: Icons.delete_forever_rounded,
            title: 'Delete server',
            detail:
                'Ends it for everybody. Channels, messages and members are '
                'gone for good.',
            action: AppButton(
              label: 'Delete server',
              variant: AppButtonVariant.danger,
              isLoading: _isBusy,
              onPressed: _isBusy ? null : _delete,
            ),
          ),
        ],
      ),
    );
  }
}
