import 'package:material_ui/material_ui.dart';

import '../../../../../logic/services/host_platform.dart';
import '../../../../../src/rust/api/screenshare/types.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import 'settings_chip.dart';
import 'settings_section.dart';

/// Whether the share shows the mouse cursor.
///
/// Auto is offered only where it differs from Show: on Windows, where a
/// whole-screen share leaves the cursor out while a game has locked the
/// mouse. Elsewhere Auto shows it, so it is drawn as Show.
class ShareCursorChoices extends StatelessWidget {
  final ShareCursor selected;
  final ValueChanged<ShareCursor> onChanged;

  const ShareCursorChoices({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final games = HostPlatform.hidesShareCursorInGames;
    final shown = selected != ShareCursor.never;
    return SettingsSection(
      label: 'Cursor',
      children: [
        SettingsChips(
          children: [
            if (games)
              SettingsChip(
                label: 'Auto',
                active: selected == ShareCursor.auto,
                onTap: () => onChanged(ShareCursor.auto),
              ),
            SettingsChip(
              label: 'Show',
              active: games ? selected == ShareCursor.always : shown,
              onTap: () => onChanged(ShareCursor.always),
            ),
            SettingsChip(
              label: 'Hide',
              active: !shown,
              onTap: () => onChanged(ShareCursor.never),
            ),
          ],
        ),
        if (games && selected == ShareCursor.auto) ...[
          const SizedBox(height: 8),
          Text(
            'Auto hides it while you play a game.',
            style: AppText.secondary.copyWith(
              color: context.theme.textTertiary,
            ),
          ),
        ],
      ],
    );
  }
}
