import 'package:flutter/material.dart';

import '../../../../../../data/classes/channel.dart';
import '../../../../../common/app_button.dart';
import '../../../servers/manage/widgets/danger_row.dart';
import '../../../servers/manage/widgets/manage_panel.dart';
import '../../channel_list/widgets/channel_menu_actions.dart';

/// The last page of a channel's settings: deleting it.
///
/// A page of its own rather than a button at the foot of Overview, so the
/// one thing here that cannot be undone is never next to a Save.
class ChannelDeletePanel extends StatefulWidget {
  final Channel channel;

  const ChannelDeletePanel({super.key, required this.channel});

  @override
  State<ChannelDeletePanel> createState() => _ChannelDeletePanelState();
}

class _ChannelDeletePanelState extends State<ChannelDeletePanel> {
  bool _isBusy = false;

  Future<void> _delete() async {
    setState(() => _isBusy = true);
    final deleted = await deleteChannel(context, widget.channel);
    if (!mounted) return;
    // Gone: the dialog notices the channel leaving the server and closes.
    if (!deleted) setState(() => _isBusy = false);
  }

  @override
  Widget build(BuildContext context) {
    final isVoice = !widget.channel.hasMessages;
    return ManagePanel(
      title: 'Delete',
      subtitle: 'Remove this channel for everyone',
      child: DangerRow(
        icon: Icons.delete_forever_rounded,
        title: 'Delete channel',
        detail: isVoice
            ? 'Anyone in a call here is disconnected. This cannot be undone.'
            : 'Every message in it is gone for everyone. This cannot be '
                  'undone.',
        action: AppButton(
          label: 'Delete channel',
          variant: AppButtonVariant.danger,
          isLoading: _isBusy,
          onPressed: _isBusy ? null : _delete,
        ),
      ),
    );
  }
}
