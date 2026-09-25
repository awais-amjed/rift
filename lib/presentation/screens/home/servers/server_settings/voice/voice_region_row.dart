import 'package:flutter/material.dart';

import '../../../../../../data/classes/livekit_node.dart';
import '../../../../../common/item_card.dart';
import '../../../../../common/row_delete_button.dart';
import '../../../../../theme/app_text.dart';
import '../../../../../theme/theme_context.dart';

/// One LiveKit node in the region list: what it is called, where it is, and
/// the two buttons that act on it.
///
/// **Nothing is edited here.** Both buttons open a dialog — one to change the
/// pair of values, one to confirm the removal — because a region is
/// infrastructure a whole server's calls land on, and neither changing its
/// address nor deleting it should be one stray click on a row in a list.
///
/// **The default has no remove button**, because it cannot be removed: it is
/// the server's own LiveKit, and offering a button the server refuses would
/// be worse than not offering one. It *is* editable, address included — that
/// write goes to the server row rather than to the node, which is the
/// dialog's business, not this row's.
class VoiceRegionRow extends StatelessWidget {
  final LiveKitNode node;
  final bool enabled;
  final VoidCallback onEdit;

  /// Null for a region that cannot be removed — the default's.
  final VoidCallback? onRemove;

  const VoiceRegionRow({
    super.key,
    required this.node,
    required this.enabled,
    required this.onEdit,
    required this.onRemove,
  });

  /// The label, plus "(default)" when that is not what it already says: an
  /// unrenamed one is called "Default", and "Default (default)" is what that
  /// produced.
  String get _title {
    if (!node.isDefault) return node.label;
    if (node.label.trim().toLowerCase() == 'default') return node.label;
    return '${node.label} (default)';
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return ItemCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _title,
                  style: AppText.row.copyWith(color: theme.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  node.url,
                  style: AppText.secondary.copyWith(
                    color: theme.textQuaternary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: enabled ? onEdit : null,
            mouseCursor: WidgetStateMouseCursor.clickable,
            icon: const Icon(Icons.edit_outlined, size: 18),
            tooltip: 'Edit region',
            color: theme.textTertiary,
          ),
          if (onRemove case final onRemove?)
            RowDeleteButton(
              tooltip: 'Remove region',
              onPressed: enabled ? onRemove : null,
            ),
        ],
      ),
    );
  }
}
