import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../data/classes/call_shortcuts.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import '../section_title.dart';
import 'call_shortcut_row.dart';

/// Keys for mute, deafen and leave, heard from anywhere. Desktop only
/// ([HostPlatform.isDesktop]) — see [CallShortcutListener].
class CallShortcutsSection extends StatelessWidget {
  final CallShortcuts shortcuts;

  /// The actions whose keys the Linux desktop holds
  /// (`AppState.desktopCallShortcuts`).
  final Set<CallShortcut> desktopActions;

  const CallShortcutsSection({
    super.key,
    required this.shortcuts,
    this.desktopActions = const {},
  });

  @override
  Widget build(BuildContext context) {
    final hint = AppText.secondary.copyWith(color: context.theme.textTertiary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SectionTitle(label: 'Shortcuts'),
        const SizedBox(height: 4),
        Text(
          'These work from anywhere, even with Rift in the background.',
          style: hint,
        ),
        // The desktop's dialog, the first time a key is given to it.
        if (!kIsWeb && Platform.isLinux)
          Text('Your computer may ask you to allow them.', style: hint),
        const SizedBox(height: 12),
        for (final action in CallShortcut.values) ...[
          if (action != CallShortcut.values.first) const SizedBox(height: 12),
          CallShortcutRow(
            action: action,
            keys: shortcuts[action],
            desktopHolds: desktopActions.contains(action),
          ),
        ],
      ],
    );
  }
}
