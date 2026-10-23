import 'package:flutter/material.dart';

import '../../data/constants.dart';
import '../theme/app_text.dart';
import '../theme/theme_context.dart';
import 'user_avatar.dart';

/// One person in a [SearchDropdownField] result list.
///
/// A null [onTap] is a result you can see but not pick: the row dims and stops
/// responding, and [trailingNote] says why. Hiding it instead reads as the
/// person not existing.
class SearchResultRow extends StatelessWidget {
  /// Shown as the row's label, and used to seed the avatar's initials.
  final String name;

  /// Stable per-person value the avatar's colour is derived from — an id, not
  /// the name, so a rename doesn't recolour them.
  final String seed;

  /// Their picture's storage path, when they have one, drawn through
  /// [UserAvatar]. It is a path on the server, not an address: handed to a
  /// network image it never loaded, and every result showed its initial.
  final String? avatarPath;

  /// Why this row can't be picked. Only meaningful when [onTap] is null.
  final String? trailingNote;

  /// Null makes the row unpickable — see the class doc.
  final VoidCallback? onTap;

  const SearchResultRow({
    super.key,
    required this.name,
    required this.seed,
    required this.onTap,
    this.avatarPath,
    this.trailingNote,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    final enabled = onTap != null;
    final radius = BorderRadius.circular(K.radiusRow);

    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          borderRadius: radius,
          hoverColor: themeState.bgHover,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            child: Row(
              spacing: 9,
              children: [
                UserAvatar(
                  avatarPath: avatarPath,
                  name: name,
                  seed: seed,
                  size: 26,
                ),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.row.copyWith(color: themeState.textPrimary),
                  ),
                ),
                if (!enabled && trailingNote != null)
                  Text(
                    trailingNote!,
                    style: AppText.label.copyWith(
                      fontWeight: FontWeight.w400,
                      color: themeState.textTertiary,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
