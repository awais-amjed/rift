import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../logic/services/host_platform.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';

/// The "Jump to…" field under the server header — the entry point to the quick
/// switcher.
///
/// It looks like a search field but is a button: the field itself lives in the
/// switcher, so there is only one place that owns the query. It takes the field
/// height and outweighs the rows beneath it, because it is the fastest route to
/// anything in the app and a pill shorter than a channel row said otherwise.
class JumpField extends StatelessWidget {
  final VoidCallback onTap;

  const JumpField({super.key, required this.onTap});

  /// The modifier is named for the platform the user is actually on —
  /// showing ⌘ on Linux would just be wrong.
  static String get shortcutLabel =>
      defaultTargetPlatform == TargetPlatform.macOS ? '⌘K' : 'Ctrl K';

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
      child: Material(
        color: themeState.bgHover,
        borderRadius: BorderRadius.circular(K.radiusRow),
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          borderRadius: BorderRadius.circular(K.radiusRow),
          hoverColor: themeState.bgActive,
          onTap: onTap,
          child: Container(
            height: K.fieldHeight,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(K.radiusRow),
              border: Border.all(color: themeState.borderElevated),
            ),
            child: Row(
              spacing: 8,
              children: [
                Icon(
                  Icons.search_rounded,
                  size: 16,
                  color: themeState.textTertiary,
                ),
                Expanded(
                  child: Text(
                    // What the switcher it opens finds, which is channels —
                    // its own box says the same. "Jump to anything…" promised
                    // people too, and typing a name found nothing. Keep it
                    // short: the sidebar is a fixed width and the Ctrl K chip
                    // takes a bite out of it.
                    HostPlatform.isMobile
                        ? 'Jump to…'
                        : 'Jump to a channel…',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    // Tertiary, not quaternary: quaternary is placeholder
                    // ink, and this is a control rather than an empty
                    // field.
                    style: AppText.secondary.copyWith(
                      color: themeState.textTertiary,
                    ),
                  ),
                ),
                // A phone has no Ctrl key to press, so the chip is
                // instructions for a keyboard that isn't there — and the
                // width it takes is width the field wanted.
                if (!HostPlatform.isMobile) _buildKbdChip(themeState),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildKbdChip(ThemeState themeState) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: themeState.bgActive,
        borderRadius: BorderRadius.circular(K.radiusRow),
      ),
      child: Text(
        shortcutLabel,
        style: AppText.kbd.copyWith(color: themeState.textTertiary),
      ),
    );
  }
}
