import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/classes/chat_message.dart';
import '../../../../data/constants.dart';
import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';
import '../../context_menu/context_menu_item.dart';
import '../../context_menu/context_menu_sheet.dart';
import '../../emoji_text.dart';
import '../../popover_surface.dart';
import '../composer/emoji_picker_panel.dart';
import '../reactions/reaction_picker.dart';
import 'message_context_menu.dart';

/// What was picked from the phone's message sheet: a quick reaction, or one
/// of the menu's actions.
sealed class MessageSheetChoice {
  const MessageSheetChoice();
}

class QuickReaction extends MessageSheetChoice {
  final String emoji;
  const QuickReaction(this.emoji);
}

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
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: theme.borderElevated,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  _Preview(message: message),
                  if (canReact) ...[
                    const SizedBox(height: 8),
                    _QuickReactions(onPick: (e) => pick(QuickReaction(e))),
                  ],
                  Divider(height: 17, color: theme.borderPrimary),
                  if (canReact)
                    ContextMenuItem(
                      icon: Icons.add_reaction_outlined,
                      label: 'Add reaction',
                      onTap: () =>
                          pick(const MenuActionChoice(MessageMenuAction.react)),
                    ),
                  if (canCopy)
                    ContextMenuItem(
                      icon: Icons.copy_rounded,
                      label: 'Copy text',
                      onTap: () =>
                          pick(const MenuActionChoice(MessageMenuAction.copy)),
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

/// Which message the sheet is about — the author and the start of what they
/// said — since the row itself is under the scrim.
class _Preview extends StatelessWidget {
  final ChatMessage message;

  const _Preview({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final text = message.text.isEmpty ? 'Attachment' : message.text;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: theme.bgHover,
        borderRadius: BorderRadius.circular(K.radiusCard),
        border: Border.all(color: theme.borderElevated),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 2,
        children: [
          Text(
            message.authorName,
            style: AppText.strong.copyWith(color: theme.textPrimary),
          ),
          Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppText.secondary.copyWith(color: theme.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _QuickReactions extends StatelessWidget {
  final ValueChanged<String> onPick;

  const _QuickReactions({required this.onPick});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(K.radiusRow);
    return GridView.count(
      crossAxisCount: 8,
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (final emoji in quickReactionEmojis)
          Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: radius,
              onTap: () => onPick(emoji),
              child: Center(
                child: Text(emoji, style: emojiRunStyle.copyWith(fontSize: 24)),
              ),
            ),
          ),
      ],
    );
  }
}
