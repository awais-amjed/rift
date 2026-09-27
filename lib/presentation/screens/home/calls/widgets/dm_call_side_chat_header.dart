import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import '../../chat/widgets/chat_header.dart';
import '../../chat/widgets/chat_header_button.dart';

/// The top of the messages beside an expanded DM call: whose conversation it
/// is, and the way to close the panel for a call with nothing beside it.
class DmCallSideChatHeader extends StatelessWidget {
  final String peerName;
  final VoidCallback onClose;

  const DmCallSideChatHeader({
    super.key,
    required this.peerName,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Container(
      height: ChatHeader.height,
      padding: const EdgeInsets.fromLTRB(16, 0, 10, 0),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.borderPrimary)),
      ),
      child: Row(
        spacing: 8,
        children: [
          Icon(
            Icons.chat_bubble_outline_rounded,
            size: K.iconRow,
            color: theme.textTertiary,
          ),
          Expanded(
            child: Text(
              peerName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.panelTitle.copyWith(color: theme.textPrimary),
            ),
          ),
          ChatHeaderButton(
            icon: Icons.close_rounded,
            tooltip: 'Hide messages',
            onTap: onClose,
          ),
        ],
      ),
    );
  }
}
