import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../data/classes/console_update.dart';
import '../../../../../logic/services/open_link.dart';
import '../../../../common/app_button.dart';
import '../../../../common/app_modal.dart';
import '../../../../common/context_menu/text_field_context_menu.dart';
import '../../../../common/field_label.dart';
import '../../../../common/icon_tile.dart';
import '../../../../common/message_markup_text.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/custom_colors.dart';
import '../../../../theme/theme_context.dart';
import '../../invites/widgets/copyable_field.dart';

/// What the console's `update` command is, run beside the stack's compose
/// file. The same words the console prints for it (`update/cli.ts`).
const String consoleUpdateCommand = 'docker compose exec console update';

/// A newer console release: how to update, then what is new in it.
Future<void> showConsoleUpdateDialog(
  BuildContext context,
  ConsoleUpdate update,
) {
  return showCustomDialog<void>(
    context: context,
    build: (_) => ConsoleUpdateDialog(update: update),
  );
}

class ConsoleUpdateDialog extends StatefulWidget {
  final ConsoleUpdate update;

  const ConsoleUpdateDialog({super.key, required this.update});

  @override
  State<ConsoleUpdateDialog> createState() => _ConsoleUpdateDialogState();
}

class _ConsoleUpdateDialogState extends State<ConsoleUpdateDialog> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(const ClipboardData(text: consoleUpdateCommand));
    if (!mounted) return;
    setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final update = widget.update;
    final notes = update.notes.trim();
    final url = Uri.tryParse(update.url);
    final linked = url != null && isOpenableLink(url);
    return AppModal(
      staysDialogOnPhone: true,
      title: 'Console ${update.version} is out',
      titleIcon: IconTile.title(
        icon: Icons.system_update_alt_rounded,
        color: CustomColors.success,
      ),
      maxWidth: 480,
      maxHeight: 600,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Run this on the machine the server runs on, in its folder, '
            'or press Update on the console\'s Overview tab.',
            style: AppText.body.copyWith(color: theme.textSecondary),
          ),
          const SizedBox(height: 10),
          CopyableField(
            value: consoleUpdateCommand,
            copied: _copied,
            onCopy: _copy,
          ),
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 18),
            FieldLabel(label: 'What\'s new', textColor: theme.textTertiary),
            const SizedBox(height: 6),
            SelectableText.rich(
              contextMenuBuilder: TextFieldContextMenu.builder,
              messageMarkupSpan(
                notes,
                base: AppText.body.copyWith(color: theme.textSecondary),
                theme: theme,
              ),
            ),
          ],
        ],
      ),
      actions: [
        if (linked)
          AppButton(
            label: 'Release page',
            variant: AppButtonVariant.secondary,
            onPressed: () => openExternalLink(update.url),
          ),
        AppButton(label: 'Close', onPressed: () => Navigator.of(context).pop()),
      ],
    );
  }
}
