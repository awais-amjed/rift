import 'package:flutter/material.dart';

import '../../../../data/classes/chat_message.dart';
import '../../../responsive/shell_scope.dart';
import '../../anchored_panel.dart';
import '../../show_custom_dialog.dart';
import 'pinned_messages_panel.dart';

/// Open the pinned list from the header's pin button, [anchor].
///
/// Hanging from the button on a desktop, a page on a phone. See
/// [PinnedMessagesPanel].
Future<void> showPinnedMessages(
  BuildContext anchor, {
  required Future<List<ChatMessage>?> Function() load,
  void Function(ChatMessage message)? onJump,
  Future<bool> Function(ChatMessage message)? onUnpin,
  Map<String, String> displayNames = const {},
}) {
  final compact = anchor.layoutMode.isCompact;
  final panel = PinnedMessagesPanel(
    load: load,
    onJump: onJump,
    onUnpin: onUnpin,
    displayNames: displayNames,
    asPage: compact,
  );
  if (compact) return showAppModal<void>(context: anchor, modal: panel);
  return showAnchoredPanel<void>(
    anchor: anchor,
    width: PinnedMessagesPanel.width,
    child: panel,
  );
}
