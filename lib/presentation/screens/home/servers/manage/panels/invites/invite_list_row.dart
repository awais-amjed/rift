import 'package:material_ui/material_ui.dart';

import '../../../../../../../data/classes/server_invite.dart';
import '../../../../../../../data/constants.dart';
import '../../../../../../common/item_card.dart';
import '../../../../../../common/row_delete_button.dart';
import '../../../../../../theme/app_text.dart';
import '../../../../../../theme/theme_context.dart';

/// One link on the Invites page: which one it is, who made it, how much of it
/// is left, and revoking it.
class InviteListRow extends StatelessWidget {
  final ServerInvite invite;

  /// The name of the role it hands out, when it hands one out.
  final String? roleName;

  final DateTime now;
  final VoidCallback? onRevoke;

  const InviteListRow({
    super.key,
    required this.invite,
    required this.now,
    this.roleName,
    this.onRevoke,
  });

  String get _title {
    final kind = invite.isBot
        ? 'Bot link'
        : roleName != null
        ? 'Gives $roleName'
        : 'Link';
    return '$kind ${invite.codeTail}';
  }

  String get _details {
    final by = invite.creatorName != null
        ? 'By ${invite.creatorName}'
        : 'By someone no longer here';
    final max = invite.maxUses;
    final uses = max == null
        ? '${invite.uses} ${invite.uses == 1 ? 'use' : 'uses'}'
        : '${invite.uses} of $max ${max == 1 ? 'use' : 'uses'}';
    return '$by · $uses · ${_expiry()}';
  }

  String _expiry() {
    final at = invite.expiresAt;
    if (at == null) return 'Never expires';
    final left = at.difference(now);
    if (left <= Duration.zero) return 'Expired';
    if (left.inHours < 1) return 'Expires in ${left.inMinutes + 1}m';
    if (left.inDays < 1) return 'Expires in ${left.inHours}h';
    return 'Expires in ${left.inDays}d';
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return ItemCard(
      child: Row(
        spacing: 10,
        children: [
          Icon(
            invite.isBot ? Icons.smart_toy_outlined : Icons.link_rounded,
            size: K.iconRow,
            color: themeState.textTertiary,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.row.copyWith(color: themeState.textPrimary),
                ),
                Text(
                  _details,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.meta.copyWith(color: themeState.textTertiary),
                ),
              ],
            ),
          ),
          RowDeleteButton(tooltip: 'Revoke', onPressed: onRevoke),
        ],
      ),
    );
  }
}
