import 'package:flutter/material.dart';

import '../../../../../../data/classes/livekit_node.dart';
import '../../../../../../data/constants.dart';
import '../../../../../theme/app_text.dart';
import '../../../../../theme/theme_context.dart';

/// One LiveKit node in the server settings list.
///
/// The default node shows no remove control, because it cannot be removed —
/// it is the server's own LiveKit URL under a label, and the field above this
/// list is where its address is changed. Offering a button the server refuses
/// would be worse than not offering one.
///
/// It is also marked as the default in words, but only when its label does
/// not already say so: a server that has never been renamed calls it
/// "Default", and "Default (default)" is what that produced.
class VoiceRegionRow extends StatelessWidget {
  final LiveKitNode node;
  final bool enabled;
  final VoidCallback onRemove;

  const VoiceRegionRow({
    super.key,
    required this.node,
    required this.enabled,
    required this.onRemove,
  });

  /// The label, plus "(default)" when that is not what it already says.
  String get _title {
    if (!node.isDefault) return node.label;
    if (node.label.trim().toLowerCase() == 'default') return node.label;
    return '${node.label} (default)';
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.bgTertiary,
        borderRadius: BorderRadius.circular(K.radiusRow),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _title,
                  style: AppText.body.copyWith(color: theme.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  node.url,
                  style: AppText.secondary.copyWith(color: theme.textQuaternary),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (!node.isDefault)
            IconButton(
              onPressed: enabled ? onRemove : null,
              mouseCursor: WidgetStateMouseCursor.clickable,
              icon: const Icon(Icons.close, size: 18),
              tooltip: 'Remove region',
              color: theme.textTertiary,
            ),
        ],
      ),
    );
  }
}
