import 'package:flutter/material.dart';

import '../../../../data/classes/chat_message.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../theme/custom_colors.dart';
import '../../../theme/app_text.dart';

/// What a message context-menu entry asked for.
enum MessageMenuAction { copy, edit, delete }

/// Right-click menu for one message. Entries are filtered by what the caller
/// says is allowed, so a menu never offers an action the server would refuse.
///
/// Anchored at the pointer via [position] (global coordinates) rather than to
/// the row, so it opens where the user actually clicked — the row spans the
/// full width and anchoring to it would put the menu far from the cursor.
Future<MessageMenuAction?> showMessageContextMenu({
  required BuildContext context,
  required Offset position,
  required ThemeState themeState,
  required ChatMessage message,
  required bool canEdit,
  required bool canDelete,
}) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (overlay == null) return null;

  final canCopy = message.text.isNotEmpty;
  if (!canCopy && !canEdit && !canDelete) return null;

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
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: themeState.borderPrimary),
    ),
    constraints: const BoxConstraints(minWidth: 172),
    items: [
      if (canCopy)
        _item(
          MessageMenuAction.copy,
          Icons.copy_rounded,
          'Copy Text',
          themeState.textSecondary,
        ),
      if (canEdit)
        _item(
          MessageMenuAction.edit,
          Icons.edit_outlined,
          'Edit Message',
          themeState.textSecondary,
        ),
      if (canDelete)
        _item(
          MessageMenuAction.delete,
          Icons.delete_outline_rounded,
          'Delete Message',
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
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 10),
        Text(
          label,
          style: AppText.rowQuiet.copyWith(fontSize: 13, color: color),
        ),
      ],
    ),
  );
}
