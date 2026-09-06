import 'package:flutter/material.dart';

import '../../../../../data/classes/role.dart';
import '../../../../../data/constants.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';

/// One role in the list, with the dot that shows what colour it paints a name.
///
/// The rank is shown, not just implied by the order. Position is the whole of
/// the delegation rule — you may only touch a role below your own — so a list
/// that only sorted by it would leave somebody guessing why the row they want
/// is refused.
class RoleRow extends StatelessWidget {
  final Role role;

  /// Null where the count is not the point — one member's own role list, where
  /// "Nobody yet" beside a role they are about to be given is both wrong and
  /// answering a question nobody asked.
  final int? memberCount;
  final bool locked;
  final VoidCallback? onTap;

  /// Null where moving is not offered — the baseline, a role out of reach, or
  /// one already at the end of the ladder.
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  const RoleRow({
    super.key,
    required this.role,
    this.memberCount,
    this.locked = false,
    this.onTap,
    this.onMoveUp,
    this.onMoveDown,
  });

  String? get _subtitle {
    if (role.isEveryone) return 'Everybody, always';
    if (role.isOwner) return 'One person, who can end or hand on the server';
    return switch (memberCount) {
      null => null,
      0 => 'Nobody yet',
      1 => '1 member',
      _ => '$memberCount members',
    };
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(K.radiusRow),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Row(
          spacing: 10,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: role.displayColor ?? themeState.textTertiary,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    role.name,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.row.copyWith(color: themeState.textPrimary),
                  ),
                  if (_subtitle case final subtitle?) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppText.secondary.copyWith(
                        color: themeState.textTertiary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (role.isOwner)
              Icon(
                Icons.workspace_premium_outlined,
                size: 14,
                color: themeState.accentBright,
              ),
            // Says which rows are out of reach before they are tapped, rather
            // than letting the database say it afterwards.
            if (locked)
              Icon(
                Icons.lock_rounded,
                size: 13,
                color: themeState.textTertiary,
              ),
            Text(
              'rank ${role.position}',
              style: AppText.meta.copyWith(color: themeState.textTertiary),
            ),
            if (onMoveUp != null || onMoveDown != null) ...[
              _Move(icon: Icons.keyboard_arrow_up_rounded, onTap: onMoveUp),
              _Move(icon: Icons.keyboard_arrow_down_rounded, onTap: onMoveDown),
            ],
          ],
        ),
      ),
    );
  }
}

class _Move extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _Move({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(K.radiusRow),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Icon(icon, size: 16, color: themeState.textTertiary),
      ),
    );
  }
}
