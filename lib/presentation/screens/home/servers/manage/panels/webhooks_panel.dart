import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/classes/channel.dart';
import '../../../../../../data/classes/server.dart';
import '../../../../../../data/enums/channel_type.dart';
import '../../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../common/field_label.dart';
import '../../../../../common/hint_card.dart';
import '../../../../../theme/theme_context.dart';
import '../../../../settings/widgets/device_dropdown.dart';
import '../../../channels/webhooks/channel_webhooks_body.dart';
import '../widgets/manage_panel.dart';

/// The webhooks page of the manage-server dialog.
///
/// A webhook belongs to a channel, so this is a channel picker over the same
/// list the channel's own menu opens. It exists because "where do I set up
/// the deploy bot" should have one answer, and that answer should not be
/// "right-click the channel".
class WebhooksPanel extends StatefulWidget {
  final Server server;

  const WebhooksPanel({super.key, required this.server});

  @override
  State<WebhooksPanel> createState() => _WebhooksPanelState();
}

class _WebhooksPanelState extends State<WebhooksPanel> {
  String? _channelId;

  /// Text channels only: a webhook posts a message, and a voice channel has
  /// nowhere to put one.
  List<Channel> get _channels => [
    for (final channel in widget.server.channels)
      if (channel.channelType == ChannelType.text) channel,
  ];

  Channel? get _channel {
    final channels = _channels;
    if (channels.isEmpty) return null;
    for (final channel in channels) {
      if (channel.id == _channelId) return channel;
    }
    return channels.first;
  }

  @override
  Widget build(BuildContext context) {
    // Live, so a channel made while the page is open shows up in the picker.
    final server =
        context.watch<ServerCubit>().state.serverById(widget.server.id) ??
        widget.server;
    final channels = [
      for (final channel in server.channels)
        if (channel.channelType == ChannelType.text) channel,
    ];
    final channel = _channel;
    final themeState = context.theme;

    return ManagePanel(
      title: 'Webhooks',
      subtitle: 'Let outside services post into a channel',
      child: channel == null
          ? const HintCard(
              icon: Icons.tag_rounded,
              text: 'No text channels yet. A webhook posts into one.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                FieldLabel(
                  label: 'Channel',
                  textColor: themeState.textTertiary,
                ),
                const SizedBox(height: 6),
                DeviceDropdown<String>(
                  icon: Icons.tag_rounded,
                  value: channel.id,
                  items: [
                    for (final c in channels)
                      DropdownMenuItem(value: c.id, child: Text('#${c.name}')),
                  ],
                  onChanged: (id) => setState(() => _channelId = id),
                ),
                const SizedBox(height: 18),
                // Keyed on the channel so switching starts a fresh list
                // rather than showing one channel's hooks under another's
                // name while the next page loads.
                ChannelWebhooksBody(
                  key: ValueKey(channel.id),
                  channel: channel,
                ),
              ],
            ),
    );
  }
}
