import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/channel.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/server_members/server_members_cubit.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/custom_colors.dart';
import '../../../../theme/theme_context.dart';

/// The channel's name with the line under it that a phone's header carries:
/// the server it belongs to — so a channel opened from a notification still
/// says where you are — and how many people are in it, or that it's private.
class ChatPhoneTitle extends StatelessWidget {
  final Channel? channel;
  final String name;

  const ChatPhoneTitle({super.key, required this.channel, required this.name});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final server = context.select<ServerCubit, String?>(
      (c) => c.state.selectedServer?.name,
    );
    final members = context.select<ServerMembersCubit, int?>(
      (c) => c.state.loaded ? c.state.peopleCount : null,
    );
    final private = channel?.isPrivate ?? false;
    final detail = [
      ?server,
      if (private)
        'private'
      else if (members != null)
        '$members ${members == 1 ? 'member' : 'members'}',
    ].join(' · ');

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          spacing: 5,
          children: [
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.panelTitle.copyWith(color: theme.textPrimary),
              ),
            ),
            if (private)
              Icon(Icons.lock_outline, size: 13, color: theme.textTertiary),
          ],
        ),
        if (detail.isNotEmpty)
          Row(
            spacing: 4,
            children: [
              if (!private)
                const Icon(
                  Icons.lock_outline,
                  size: 11,
                  color: CustomColors.success,
                ),
              Flexible(
                child: Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.label.copyWith(color: theme.textTertiary),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
