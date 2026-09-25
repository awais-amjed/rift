import 'package:flutter/material.dart';

import '../../../../../data/classes/channel.dart';
import '../../../../../data/constants.dart';
import '../../../../common/app_button.dart';
import '../../../../common/app_modal.dart';
import '../../../../theme/theme_context.dart';
import 'channel_webhooks_body.dart';

/// [ChannelWebhooksBody] in a dialog of its own, for the channel's menu.
class ChannelWebhooksDialog extends StatelessWidget {
  final Channel channel;

  const ChannelWebhooksDialog({super.key, required this.channel});

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return AppModal(
      title: 'Webhooks',
      subtitle: '#${channel.name}',
      maxHeight: 560,
      titleIcon: Icon(
        Icons.webhook_rounded,
        size: K.iconButton,
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
    );
  }
}
