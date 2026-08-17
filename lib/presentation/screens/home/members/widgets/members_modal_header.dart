import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/icon_tile.dart';
import '../../../../theme/app_text.dart';

/// The members dialog's own header: how many members, which server, and the way
/// out.
///
/// The dialog hand-rolls its chrome rather than using [AppModal] because its body
/// is a `ListView` that scrolls internally, so the header is a widget of its own
/// instead of a parameter.
class MembersModalHeader extends StatelessWidget {
  /// Null while the roster is still loading, when the count is not yet known.
  final int? count;

  /// Named because this dialog opens from the rail for any server, not only the
  /// one whose channels are on screen behind it.
  final String serverName;

  final ThemeState themeState;

  const MembersModalHeader({
    super.key,
    required this.count,
    required this.serverName,
    required this.themeState,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 14, 16),
      child: Row(
        children: [
          IconTile(
            icon: Icons.group_outlined,
            color: themeState.accentBright,
            size: 36,
            radius: K.radiusButton,
            iconSize: 18,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  count == null ? 'Members' : 'Members — $count',
                  style: AppText.row.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: themeState.textPrimary,
                  ),
                ),
                Text(
                  serverName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.secondary.copyWith(
                    fontSize: 12,
                    color: themeState.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.close, size: 18, color: themeState.textTertiary),
          ),
        ],
      ),
    );
  }
}
