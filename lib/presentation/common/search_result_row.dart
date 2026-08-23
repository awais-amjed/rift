import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../logic/cubits/theme/theme_cubit.dart';
import '../theme/app_text.dart';
import 'squircle_avatar.dart';

/// One person in a [SearchDropdownField] result list.
///
/// Both DM drop-downs land on the same row — a server's members and central's
/// handle directory are the same question asked of two directories — so the row
/// is shared and takes what differs as parameters. Forking it once meant the
/// two lists drifting apart under the same field.
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

  /// Their avatar, when they have one. Falls back to initials.
  final String? imageUrl;

  /// Why this row can't be picked. Only meaningful when [onTap] is null.
  final String? trailingNote;

  /// Null makes the row unpickable — see the class doc.
  final VoidCallback? onTap;

  const SearchResultRow({
    super.key,
    required this.name,
    required this.seed,
    required this.onTap,
    this.imageUrl,
    this.trailingNote,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeCubit>().state;
    final enabled = onTap != null;
    final radius = BorderRadius.circular(9);

    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          hoverColor: themeState.bgHover,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            child: Row(
              spacing: 9,
              children: [
                SquircleAvatar(
                  name: name,
                  seed: seed,
                  imageUrl: imageUrl,
                  size: 26,
                ),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.row.copyWith(
                      fontSize: 13,
                      color: themeState.textPrimary,
                    ),
                  ),
                ),
                if (!enabled && trailingNote != null)
                  Text(
                    trailingNote!,
                    style: AppText.label.copyWith(
                      fontWeight: FontWeight.w400,
                      color: themeState.textQuaternary,
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
