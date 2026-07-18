import 'package:flutter/material.dart';

import '../../../../../data/classes/dm_conversation.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';

/// One conversation row in the Home panel: tier icon, name, decrypted
/// preview.
class DmConversationTile extends StatelessWidget {
  final DmConversation conversation;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;
  final ThemeState themeState;

  const DmConversationTile({
    super.key,
    required this.conversation,
    required this.icon,
    required this.isSelected,
    required this.onTap,
    required this.themeState,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? themeState.channelActiveBg : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        hoverColor: themeState.bgHover,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Icon(
                icon,
                size: 17,
                color: isSelected
                    ? themeState.primary
                    : themeState.textQuaternary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      conversation.peerName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isSelected
                            ? themeState.channelActiveText
                            : themeState.textSecondary,
                      ),
                    ),
                    if (conversation.lastMessage != null)
                      Text(
                        conversation.lastMessage!.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: themeState.textQuaternary,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
