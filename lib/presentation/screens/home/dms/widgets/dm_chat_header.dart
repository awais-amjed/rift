import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/squircle_avatar.dart';
import '../../../../common/status_chip.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/custom_colors.dart';
import '../../chat/widgets/chat_header.dart';
import '../../chat/widgets/chat_header_button.dart';

/// Header of an open DM conversation.
///
/// Carries two chips rather than one: which tier the conversation is on, and
/// that it's encrypted. The tier matters here in a way it doesn't in a
/// channel — a central DM is quota-limited and a server DM isn't, and that's
/// worth saying before someone starts typing.
class DmChatHeader extends StatelessWidget {
  final String title;

  /// The peer's id, so their avatar matches the conversation list.
  final String? peerId;

  /// Which tier this conversation is on — "Central", or the server's name.
  final String tierLabel;

  final IconData tierIcon;
  final VoidCallback onClose;

  const DmChatHeader({
    super.key,
    required this.title,
    required this.tierLabel,
    required this.tierIcon,
    required this.onClose,
    this.peerId,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeCubit>().state;

    return Container(
      height: ChatHeader.height,
      padding: const EdgeInsets.fromLTRB(16, 0, 10, 0),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: themeState.borderPrimary)),
      ),
      child: Row(
        spacing: 10,
        children: [
          SquircleAvatar(name: title, seed: peerId, size: 26),
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.panelTitle.copyWith(color: themeState.textPrimary),
            ),
          ),
          StatusChip(
            icon: tierIcon,
            label: tierLabel,
            color: themeState.accentBright,
          ),
          const StatusChip(
            icon: Icons.lock_outline,
            label: 'Encrypted',
            color: CustomColors.success,
          ),
          const Spacer(),
          ChatHeaderButton(
            icon: Icons.close_rounded,
            tooltip: 'Close conversation',
            onTap: onClose,
          ),
        ],
      ),
    );
  }
}
