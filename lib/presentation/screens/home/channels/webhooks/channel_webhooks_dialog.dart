import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/channel.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/app_button.dart';
import '../../../../common/app_modal.dart';
import 'channel_webhooks_body.dart';

/// [ChannelWebhooksBody] in a dialog of its own, for the channel's menu.
class ChannelWebhooksDialog extends StatelessWidget {
  final Channel channel;

  const ChannelWebhooksDialog({super.key, required this.channel});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) => AppModal(
        title: 'Webhooks',
        subtitle: '#${channel.name}',
        maxHeight: 560,
        titleIcon: Icon(
          Icons.webhook_rounded,
          size: 18,
          color: themeState.primary,
        ),
        content: ChannelWebhooksBody(channel: channel),
        actions: [
          AppButton(
            label: 'Done',
            variant: AppButtonVariant.secondary,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}
