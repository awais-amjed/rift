import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../chat/widgets/chat_header_button.dart';

/// How much of the window a DM call has, from its own strip: Expand when it
/// shares the pane with its messages, and — expanded — the messages beside
/// it on and off, and Collapse back to the split.
class DmCallLayoutButtons extends StatelessWidget {
  /// Whether the call is the split's upper half rather than the whole pane.
  final bool split;

  const DmCallLayoutButtons({super.key, required this.split});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppCubit>();
    if (split) {
      return ChatHeaderButton(
        icon: Icons.open_in_full_rounded,
        tooltip: 'Expand call',
        onTap: () => app.setDmCallExpanded(true),
      );
    }
    final chatOpen = context.select<AppCubit, bool>(
      (c) => c.state.dmCallChatOpen,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        ChatHeaderButton(
          icon: chatOpen
              ? Icons.chat_bubble_rounded
              : Icons.chat_bubble_outline_rounded,
          tooltip: chatOpen ? 'Hide messages' : 'Show messages',
          isPrimary: chatOpen,
          onTap: app.toggleDmCallChat,
        ),
        ChatHeaderButton(
          icon: Icons.close_fullscreen_rounded,
          tooltip: 'Collapse call',
          onTap: () => app.setDmCallExpanded(false),
        ),
      ],
    );
  }
}
