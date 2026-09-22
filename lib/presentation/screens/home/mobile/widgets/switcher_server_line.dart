import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/channel_presence/channel_presence_cubit.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/custom_colors.dart';
import '../../../../theme/theme_context.dart';

/// A server's second line: that it is encrypted, and who is here.
///
/// Presence is followed for the selected server only, which is the one this
/// header names, so the count is live and costs nothing to read.
class SwitcherServerLine extends StatelessWidget {
  final String serverId;

  const SwitcherServerLine({super.key, required this.serverId});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final online = context.select<ChannelPresenceCubit, int>(
      (c) => c.state.onlineUserIds.length,
    );
    return Row(
      spacing: 5,
      children: [
        const Icon(Icons.lock_outline, size: 11, color: CustomColors.success),
        Text(
          '$online online',
          style: AppText.label.copyWith(color: theme.textTertiary),
        ),
      ],
    );
  }
}
