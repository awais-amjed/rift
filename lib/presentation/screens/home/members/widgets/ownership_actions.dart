import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/server_member.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/helper_methods.dart';
import '../../../../common/confirm_dialog.dart';

/// The one thing an owner does to a member that nobody else can: make them
/// the owner instead.
///
/// Asked first, in words that say what is being given up. There is no undo —
/// the moment the row lands, the other person is the only one who could give
/// it back.
class OwnershipActions {
  const OwnershipActions._();

  /// Whether [member] is somebody the viewer could hand the server to.
  ///
  /// The database refuses a bot, a banned member and yourself; this is what
  /// keeps the row from being offered and then refused.
  static bool canTransferTo(ServerCubit cubit, ServerMember member) {
    final me = cubit.state.selectedServer?.user;
    return (me?.permissions.isOwner ?? false) &&
        me?.id != member.id &&
        !member.isBot &&
        !member.isBanned;
  }

  static Future<void> transfer(
    BuildContext context,
    ServerMember member,
  ) async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Make ${member.displayName} the owner?',
      message:
          'They become the one person who can delete this server or hand it '
          'on. You stay an admin. This cannot be undone from your side.',
      confirmLabel: 'Transfer ownership',
      icon: Icons.workspace_premium_outlined,
      isDestructive: true,
    );
    if (!confirmed || !context.mounted) return;

    final result = await context.read<ServerCubit>().transferOwnership(
      member.id,
    );
    if (result.success) {
      HelperMethods.showSuccess(
        message: '${member.displayName} now owns this server',
      );
    } else {
      HelperMethods.showError(error: result.error ?? 'Could not transfer');
    }
  }
}
