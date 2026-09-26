import 'package:flutter/material.dart';

import '../../../../../../data/classes/channel.dart';
import '../../../servers/manage/widgets/manage_panel.dart';
import '../../webhooks/channel_webhooks_body.dart';

/// A text channel's webhooks — the same list the Webhooks page of Manage
/// server shows under its channel picker.
class ChannelWebhooksPanel extends StatelessWidget {
  final Channel channel;

  const ChannelWebhooksPanel({super.key, required this.channel});

  @override
  Widget build(BuildContext context) {
    return ManagePanel(
      title: 'Webhooks',
      subtitle: 'Let outside services post into this channel',
      child: ChannelWebhooksBody(channel: channel),
    );
  }
}
