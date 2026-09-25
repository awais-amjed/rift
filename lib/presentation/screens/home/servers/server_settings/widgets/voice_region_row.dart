import 'package:flutter/material.dart';

import '../../../../../../data/classes/livekit_node.dart';
import '../../../../../../data/constants.dart';
import '../../../../../theme/app_text.dart';
import '../../../../../theme/theme_context.dart';
import 'inline_edit_text.dart';

/// One LiveKit node in the server settings list, with both of its fields
/// editable in place — see [InlineEditText].
///
/// **The name is editable, the default's most of all.** The label is what a
/// channel manager picks from and what a member is shown, so it should be a
/// place; and the one node every server is guaranteed to have is created
/// called "Default", which is the one name that is never a place. It is also
/// the likeliest to need renaming, being whatever box the server already runs
/// on.
///
/// **The address is editable for every region but the default**, and that
/// asymmetry is the honest one. The default node *is* `servers.livekit_url` —
/// the LiveKit URL field higher up this same dialog edits that column, and a
/// trigger carries it here. Two controls for one value, one applying on Save
/// and the other immediately, would be a race with a confusing winner. So the
/// default's address stays text and says where to change it; every other
/// region owns its own, and a box that moves is a click rather than a delete
/// and a re-add.
///
/// The default also has no *remove* control, because it cannot be removed.
/// Offering a button the server refuses would be worse than not offering one.
class VoiceRegionRow extends StatelessWidget {
  final LiveKitNode node;
  final bool enabled;
  final VoidCallback onRemove;

  /// Called with the new label, trimmed and known to differ.
  final ValueChanged<String> onRename;

  /// Called with the new address, trimmed, known to differ and known to look
  /// like a WebSocket URL.
  final ValueChanged<String> onRetarget;

  /// Told when an edit was refused before it was sent, so the section can say
  /// why rather than letting a constraint answer for it.
  final ValueChanged<String> onInvalid;

  const VoiceRegionRow({
    super.key,
    required this.node,
    required this.enabled,
    required this.onRemove,
    required this.onRename,
    required this.onRetarget,
    required this.onInvalid,
  });

  /// The label, plus "(default)" when that is not what it already says: an
  /// unrenamed one is called "Default", and "Default (default)" is what that
  /// produced.
  String get _title {
    if (!node.isDefault) return node.label;
    if (node.label.trim().toLowerCase() == 'default') return node.label;
    return '${node.label} (default)';
  }

  /// The address a client connects to, or the sentence saying why it is not.
  ///
  /// Checked here so a typo is a sentence rather than a database constraint —
  /// `livekit_nodes.url` insists on the same shape, and being told by the
  /// server would be both slower and worse worded. Public so the agreement
  /// between the two can be tested.
  static String? checkUrl(String value) {
    if (!RegExp(r'^wss?://[^ ]+$').hasMatch(value)) {
      return 'A region address starts with ws:// or wss:// and has no spaces.';
    }
    return null;
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
                InlineEditText(
                  display: _title,
                  value: node.label,
                  style: AppText.body.copyWith(color: theme.textPrimary),
                  hint: 'Region name',
                  maxLength: 40,
                  enabled: enabled,
                  onCommit: onRename,
                ),
                const SizedBox(height: 2),
                if (node.isDefault)
                  Tooltip(
                    message: 'Change this in the LiveKit URL field above',
                    child: Text(
                      node.url,
                      style: AppText.secondary.copyWith(
                        color: theme.textQuaternary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                else
                  InlineEditText(
                    display: node.url,
                    value: node.url,
                    style: AppText.secondary.copyWith(
                      color: theme.textQuaternary,
                    ),
                    hint: 'wss://example.com',
                    validate: checkUrl,
                    enabled: enabled,
                    onCommit: onRetarget,
                    onInvalid: onInvalid,
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
