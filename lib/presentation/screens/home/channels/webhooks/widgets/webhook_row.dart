import 'package:flutter/material.dart';

import '../../../../../../data/classes/webhook.dart';
import '../../../../../../data/constants.dart';
import '../../../../../theme/app_text.dart';
import '../../../../../theme/custom_colors.dart';
import '../../../../../theme/theme_context.dart';

/// One existing webhook in the list: its name, when it last posted, and the
/// only thing that can still be done to it.
///
/// There is no "copy URL" here and there never will be — the URL was shown once
/// when it was minted and the server keeps only a hash of it. A row that
/// offered to copy it would be promising something the schema deliberately
/// cannot do.
class WebhookRow extends StatelessWidget {
  final Webhook webhook;
  final VoidCallback? onDelete;

  const WebhookRow({super.key, required this.webhook, this.onDelete});

  /// "never used" is the interesting state, so it is spelled out rather than
  /// left blank — a credential nothing has used is one worth revoking.
  String get _lastUsed {
    final at = webhook.lastUsedAt;
    if (at == null) return 'Never used';
    final ago = DateTime.now().difference(at);
    if (ago.inMinutes < 1) return 'Used just now';
    if (ago.inHours < 1) return 'Used ${ago.inMinutes}m ago';
    if (ago.inDays < 1) return 'Used ${ago.inHours}h ago';
    return 'Used ${ago.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: themeState.bgTertiary,
        borderRadius: BorderRadius.circular(K.radiusRow),
        border: Border.all(color: themeState.borderElevated),
      ),
      child: Row(
        spacing: 10,
        children: [
          Icon(Icons.webhook_rounded, size: 16, color: themeState.textTertiary),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  webhook.name,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.row.copyWith(color: themeState.textPrimary),
                ),
                Text(
                  _lastUsed,
                  style: AppText.meta.copyWith(color: themeState.textTertiary),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onDelete,
            tooltip: 'Revoke',
            iconSize: 16,
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.delete_outline_rounded, color: CustomColors.error),
          ),
        ],
      ),
    );
  }
}
