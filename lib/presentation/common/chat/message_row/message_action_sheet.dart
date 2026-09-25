import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/classes/chat_message.dart';
import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../theme/theme_context.dart';
import '../../context_menu/context_menu_item.dart';
import '../../context_menu/context_menu_sheet.dart';
import '../../popover_surface.dart';
import '../../sheet_handle.dart';
import '../composer/emoji_picker_panel.dart';
import '../reactions/reaction_picker.dart';
import 'message_context_menu.dart';
import 'message_sheet_preview.dart';
import 'message_sheet_quick_reactions.dart';

/// What was picked from the phone's message sheet: a quick reaction, or one
/// of the menu's actions.
sealed class MessageSheetChoice {
  const MessageSheetChoice();
}

/// One of the quick reactions across the top of the sheet.
class QuickReaction extends MessageSheetChoice {
  final String emoji;
  const QuickReaction(this.emoji);
}

/// One of the menu's actions, the same list a desktop right-click shows.
class MenuActionChoice extends MessageSheetChoice {
  final MessageMenuAction action;
  const MenuActionChoice(this.action);
}

/// The message menu on a phone: the same actions in the same order, as a
/// bottom sheet, with the quick reactions laid across its top.
///
/// Reacting is the commonest thing a long press is for, and on a desktop it
/// is one hover away. A sheet that made it a row, then a second popover,
/// would have turned the most frequent action into the slowest — so the
/// sixteen [quickReactionEmojis] are right there, in their fixed two rows of
/// eight, and "Add reaction" opens the full picker for anything else.
Future<MessageSheetChoice?> showMessageActionSheet({
  required BuildContext context,
  required ChatMessage message,
  required bool canReact,
  required bool canEdit,
  required bool canDelete,
  bool canReply = false,
  bool canForward = false,
  bool canPin = false,
}) {
  final theme = context.theme;
  final themeCubit = context.read<ThemeCubit>();
  final canCopy = message.text.isNotEmpty;
  return showModalBottomSheet<MessageSheetChoice>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: theme.bgElevated,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(PopoverSurface.radius),
      ),
    ),
    builder: (sheet) {
      void pick(MessageSheetChoice choice) => Navigator.of(sheet).pop(choice);
      // Rows draw at a thumb's size inside a sheet; nothing here submenus.
      // The theme is handed over because a sheet is a route of its own, and
      // not every host provides cubits above its navigator.
      return BlocProvider.value(
        value: themeCubit,
        child: ContextMenuPresentation(
          pushSubmenu: (_) {},
          popSubmenu: null,
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SheetHandle(margin: EdgeInsets.only(bottom: 10)),
                  MessageSheetPreview(message: message),
                  if (canReact) ...[
                    const SizedBox(height: 8),
                    MessageSheetQuickReactions(
                      onPick: (e) => pick(QuickReaction(e)),
                    ),
                  ],
                  Divider(height: 17, color: theme.borderPrimary),
                  if (canReact)
                    ContextMenuItem(
                      icon: Icons.add_reaction_outlined,
                      label: 'Add reaction',
                      onTap: () =>
                          pick(const MenuActionChoice(MessageMenuAction.react)),
                    ),
                  if (canReply)
                    ContextMenuItem(
                      icon: Icons.reply_rounded,
                      label: 'Reply',
                      onTap: () =>
                          pick(const MenuActionChoice(MessageMenuAction.reply)),
                    ),
                  if (canForward)
                    ContextMenuItem(
                      icon: Icons.forward_rounded,
                      label: 'Forward',
                      onTap: () => pick(
                        const MenuActionChoice(MessageMenuAction.forward),
                      ),
                    ),
                  if (canCopy)
                    ContextMenuItem(
                      icon: Icons.copy_rounded,
                      label: 'Copy text',
                      onTap: () =>
                          pick(const MenuActionChoice(MessageMenuAction.copy)),
                    ),
                  if (canPin)
                    ContextMenuItem(
                      icon: message.isPinned
                          ? Icons.push_pin_rounded
                          : Icons.push_pin_outlined,
                      label: message.isPinned ? 'Unpin message' : 'Pin message',
                      onTap: () =>
                          pick(const MenuActionChoice(MessageMenuAction.pin)),
                    ),
                  if (canEdit)
                    ContextMenuItem(
                      icon: Icons.edit_outlined,
                      label: 'Edit message',
                      onTap: () =>
                          pick(const MenuActionChoice(MessageMenuAction.edit)),
                    ),
                  if (canDelete)
                    ContextMenuItem(
                      icon: Icons.delete_outline_rounded,
                      label: 'Delete message',
                      isDangerous: true,
                      onTap: () => pick(
                        const MenuActionChoice(MessageMenuAction.delete),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// The full emoji picker as a sheet, answering with the one emoji picked.
Future<String?> showEmojiReactionSheet(BuildContext context) {
  final theme = context.theme;
  final themeCubit = context.read<ThemeCubit>();
  final appCubit = context.read<AppCubit>();
  return showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    backgroundColor: theme.bgElevated,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(PopoverSurface.radius),
      ),
    ),
    builder: (sheet) => MultiBlocProvider(
      providers: [
        BlocProvider.value(value: themeCubit),
        BlocProvider.value(value: appCubit),
      ],
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: EmojiPickerPanel.height + 40,
          child: EmojiPickerPanel(
            onSelected: (emoji) => Navigator.of(sheet).pop(emoji),
          ),
        ),
      ),
    ),
  );
}
