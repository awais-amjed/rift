import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/apis/moderation_api.dart';
import '../../../../../data/apis/voice_api.dart';
import '../../../../../data/repositories/session_repository.dart';
import '../../../../../logic/helper_methods.dart';
import '../../../../common/confirm_dialog.dart';
import '../../../../common/context_menu/context_menu_item.dart';
import '../../../../common/context_menu_region.dart';
import '../../members/widgets/kick_confirm.dart';

/// The three ways to remove someone, which are not the same tool.
///
/// **Disconnect** ends their connections to this call and nothing else. They
/// may walk straight back in; nothing is written down. It is for defusing a
/// moment — a hot mic in an empty room — and it deliberately does not ask for
/// confirmation, because the worst case is that someone rejoins.
///
/// **Kick** removes them from the server until a new invite brings them back,
/// without their roles or private channels. It asks first, like a ban.
///
/// **Ban** is the persistent one: RLS refuses them everything on the server
/// afterwards, and they are removed from every live call on the way out. It
/// asks first, because nothing about it is a small mistake.
///
/// Only banning is admin-only. Disconnect follows "Move to" — the same staff
/// authority over a call — because it is the same size of act. Kick is its own
/// permission, `KICK_MEMBERS`.
///
/// There is no unban here on purpose. A banned member cannot be a live
/// participant, so this menu can only ever be looking at someone who isn't
/// banned; showing them a toggle would be showing them a constant. Unbanning
/// lives in the Members dialog, which reads the real state.
class ParticipantRemovalItems extends StatelessWidget {
  final String targetUserId;
  final String name;

  /// May disconnect: staff, and only when there is a call to remove them from.
  final bool canDisconnect;

  /// May kick: `KICK_MEMBERS`, and not against an admin or a bot.
  final bool canKick;

  /// May ban: server admins, matching `moderate_user`'s own rule.
  final bool canBan;

  const ParticipantRemovalItems({
    super.key,
    required this.targetUserId,
    required this.name,
    required this.canDisconnect,
    required this.canKick,
    required this.canBan,
  });

  Future<void> _disconnect(BuildContext context) async {
    // Dismissed up front: the menu is about a participant who is about to stop
    // being one, and leaving it open over an empty tile reads as a no-op.
    ContextMenuScope.of(context)?.call();
    final voice = VoiceApi(session: context.read<SessionRepository>());
    final response = await voice.kickUser(userId: targetUserId);
    if (response.success) return;
    HelperMethods.showToast(
      title: 'Could not disconnect',
      description: '${response.error}',
    );
  }

  Future<void> _kick(BuildContext context) async {
    // Read before the await, for the same reason as [_ban].
    final moderation = ModerationApi(
      session: context.read<SessionRepository>(),
    );
    if (!await confirmKick(context, name)) return;
    final response = await moderation.kickMember(userId: targetUserId);
    if (response.success) {
      HelperMethods.showToast(
        title: 'Kicked',
        description: '$name is out until a new invite.',
      );
      return;
    }
    HelperMethods.showToast(
      title: 'Could not kick',
      description: '${response.error}',
    );
  }

  Future<void> _ban(BuildContext context) async {
    // Reads before the await: confirming dismisses the menu this widget lives
    // in, so the session has to be in hand before the tree goes.
    final moderation = ModerationApi(
      session: context.read<SessionRepository>(),
    );
    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Ban $name?',
      message:
          'They lose access to this server immediately, including anything '
          'they are in the middle of. Their messages stay. You can lift it '
          'again from the Members dialog.',
      confirmLabel: 'Ban',
      icon: Icons.gavel_rounded,
      isDestructive: true,
    );
    if (!confirmed) return;

    final response = await moderation.moderateUser(
      userId: targetUserId,
      isBanned: true,
    );
    if (response.success) {
      HelperMethods.showToast(title: 'Banned', description: '$name is out.');
      return;
    }
    HelperMethods.showToast(
      title: 'Could not ban',
      description: '${response.error}',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!canDisconnect && !canKick && !canBan) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (canDisconnect)
          ContextMenuItem(
            icon: Icons.call_end_rounded,
            label: 'Disconnect',
            isDangerous: true,
            onTap: () => _disconnect(context),
          ),
        if (canKick)
          ContextMenuItem(
            icon: Icons.logout_rounded,
            label: 'Kick from server',
            isDangerous: true,
            // The confirm dialog dismisses the menu, as for Ban.
            onTap: () => _kick(context),
          ),
        if (canBan)
          ContextMenuItem(
            icon: Icons.gavel_rounded,
            label: 'Ban from server',
            isDangerous: true,
            // Nothing dismisses here — showConfirmDialog does it on the way in,
            // and doing it twice would take the dialog down with the menu.
            onTap: () => _ban(context),
          ),
      ],
    );
  }
}
