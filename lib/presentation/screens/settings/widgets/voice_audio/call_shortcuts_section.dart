import 'package:flutter/material.dart';

import '../../../../../data/classes/call_shortcuts.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import '../section_title.dart';
import 'call_shortcut_row.dart';

/// Keys for mute and deafen. Desktop only ([HostPlatform.isDesktop]), and
/// only while Rift's window is in front — see [CallShortcutListener].
class CallShortcutsSection extends StatelessWidget {
  final CallShortcuts shortcuts;

  const CallShortcutsSection({super.key, required this.shortcuts});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SectionTitle(label: 'Shortcuts'),
        const SizedBox(height: 4),
        Text(
          'These work while Rift is the window in front.',
          style: AppText.secondary.copyWith(color: context.theme.textTertiary),
        ),
        const SizedBox(height: 12),
        for (final action in CallShortcut.values) ...[
          if (action != CallShortcut.values.first) const SizedBox(height: 12),
          CallShortcutRow(action: action, keys: shortcuts[action]),
        ],
      ],
    );
  }
}
