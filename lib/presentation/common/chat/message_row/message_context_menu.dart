import 'package:flutter/material.dart';

import '../../../../data/classes/chat_message.dart';
import '../../../../data/constants.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../theme/app_text.dart';
import '../../../theme/custom_colors.dart';

/// What a message context-menu entry asked for.
enum MessageMenuAction { react, reply, forward, copy, edit, delete }

/// Right-click — and long-press — menu for one message. Entries are filtered
/// by what the caller says is allowed, so a menu never offers an action the
/// server would refuse.
///
/// **React is in here as well as in the hover toolbar**, which is not a
/// duplicate so much as the only way to reach it at all without a mouse: the
/// toolbar appears on hover, and a finger never hovers. Right-clicking to
/// react is a reasonable path on a desktop too, so it is offered everywhere
/// rather than only on a phone — a menu whose entries move around depending
/// on the window is worse than one entry more than strictly needed.
///
/// Anchored at the pointer via [position] (global coordinates) rather than to
/// the row, so it opens where the user actually clicked — the row spans the
/// full width and anchoring to it would put the menu far from the cursor.
Future<MessageMenuAction?> showMessageContextMenu({
  required BuildContext context,
  required Offset position,
  required ThemeState themeState,
  required ChatMessage message,
  required bool canReact,
  required bool canEdit,
  required bool canDelete,
  bool canReply = false,
  bool canForward = false,
}) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (overlay == null) return null;

  final canCopy = message.text.isNotEmpty;
  if (!canReact &&
      !canReply &&
      !canForward &&
      !canCopy &&
      !canEdit &&
      !canDelete) {
    return null;
  }

  return showMenu<MessageMenuAction>(
    context: context,
    position: RelativeRect.fromRect(
      position & Size.zero,
      Offset.zero & overlay.size,
    ),
    color: themeState.bgElevated,
    // Kill the Material-3 elevation surface tint — it darkens the popover.
    surfaceTintColor: Colors.transparent,
    elevation: 6,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(K.radiusCard),
      side: BorderSide(color: themeState.borderPrimary),
    ),
    constraints: const BoxConstraints(minWidth: 172),
    items: [
      if (canReact)
        _item(
          MessageMenuAction.react,
          Icons.add_reaction_outlined,
          'Add reaction',
          themeState.textSecondary,
        ),
      if (canReply)
        _item(
          MessageMenuAction.reply,
          Icons.reply_rounded,
          'Reply',
          themeState.textSecondary,
        ),
      if (canForward)
        _item(
          MessageMenuAction.forward,
          Icons.forward_rounded,
          'Forward',
          themeState.textSecondary,
        ),
      if (canCopy)
        _item(
          MessageMenuAction.copy,
          Icons.copy_rounded,
          'Copy text',
          themeState.textSecondary,
        ),
      if (canEdit)
        _item(
          MessageMenuAction.edit,
          Icons.edit_outlined,
          'Edit message',
          themeState.textSecondary,
        ),
      if (canDelete)
        _item(
          MessageMenuAction.delete,
          Icons.delete_outline_rounded,
          'Delete message',
          CustomColors.error,
        ),
    ],
  );
}

PopupMenuItem<MessageMenuAction> _item(
  MessageMenuAction action,
  IconData icon,
  String label,
  Color color,
) {
  return PopupMenuItem<MessageMenuAction>(
    value: action,
    height: 38,
    child: Row(
      children: [
        Icon(icon, size: K.iconRow, color: color),
        const SizedBox(width: 10),
        Text(label, style: AppText.rowQuiet.copyWith(color: color)),
      ],
    ),
  );
}
