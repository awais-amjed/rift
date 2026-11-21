import 'package:material_ui/material_ui.dart';

import '../../../../../data/classes/call_shortcuts.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import '../keybinds/call_shortcut_row.dart';
import '../section_title.dart';

/// The clip shortcut, the same row as in Keybinds, so it can be set beside
/// the switch it needs. Either place changes the one key.
class ClipShortcutSection extends StatelessWidget {
  final AppState appState;

  const ClipShortcutSection({super.key, required this.appState});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SectionTitle(label: 'Shortcut'),
        const SizedBox(height: 4),
        Text(
          'Works with Rift in the background too. It is also under Keybinds.',
          style: AppText.secondary.copyWith(color: context.theme.textTertiary),
        ),
        const SizedBox(height: 12),
        CallShortcutRow(
          action: CallShortcut.clip,
          keys: appState.callShortcuts[CallShortcut.clip],
          desktopKey: appState.desktopCallShortcuts[CallShortcut.clip],
        ),
      ],
    );
  }
}
