import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/classes/channel.dart';
import '../../../../../../data/enums/channel_type.dart';
import '../../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../../logic/helper_methods.dart';
import '../../../../../common/app_modal.dart';
import '../../../../../common/confirm_dialog.dart';
import '../../../../../common/context_menu/context_menu_item.dart';
import '../../../../../common/context_menu/context_menu_panel.dart';
import '../../../../../common/context_menu_region.dart';
import '../../rename_channel_dialog.dart';

/// Right-click menu for a channel in the sidebar — rename and delete.
///
/// Channel managers only. Members get no menu at all rather than a menu of
/// things that would be refused: `channels_update_managers` and
/// `channels_delete_managers` decide either way, so this is only about not
/// offering what won't work.
class ChannelContextMenu extends StatelessWidget {
  final Channel channel;

  const ChannelContextMenu({super.key, required this.channel});

  /// Wraps [child] in the menu when the caller may manage channels, and
  /// returns it untouched when they may not — so a member's right-click falls
  /// through to whatever is underneath instead of opening an empty panel.
  static Widget wrap({
    required BuildContext context,
    required Channel channel,
    required Widget child,
  }) {
    final canManage =
        context
            .watch<ServerCubit>()
            .state
            .selectedServer
            ?.user
            ?.permissions
            .isChannelManager ??
        false;
    if (!canManage) return child;
    return ContextMenuRegion(
      contextMenu: ChannelContextMenu(channel: channel),
      child: child,
    );
  }

  void _rename(BuildContext context) {
    ContextMenuScope.of(context)?.call();
    showCustomDialog(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<ServerCubit>(),
        child: RenameChannelDialog(channel: channel),
      ),
    );
  }

  Future<void> _delete(BuildContext context) async {
    ContextMenuScope.of(context)?.call();
    final serverCubit = context.read<ServerCubit>();
    final isVoice = channel.channelType == ChannelType.voice;

    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Delete #${channel.name}?',
      message: isVoice
          ? 'Anyone in this call will be disconnected. The channel and its '
                'history are gone for everyone, and this cannot be undone.'
          : 'The channel and every message in it are gone for everyone, and '
                'this cannot be undone.',
      confirmLabel: 'Delete channel',
      icon: Icons.delete_outline_rounded,
      isDestructive: true,
    );
    if (!confirmed) return;

    final result = await serverCubit.deleteChannel(channel.id);
    if (!result.success) {
      HelperMethods.showError(
        error: result.error ?? 'Could not delete that channel',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isVoice = channel.channelType == ChannelType.voice;

    return ContextMenuPanel(
      heading: isVoice ? 'Voice channel' : 'Text channel',
      subheading: channel.name,
      leading: Icon(
        isVoice ? Icons.volume_up_rounded : Icons.tag_rounded,
        size: 16,
        color: context.watch<ThemeCubit>().state.textTertiary,
      ),
      children: [
        ContextMenuItem(
          icon: Icons.drive_file_rename_outline_rounded,
          label: 'Rename',
          onTap: () => _rename(context),
        ),
        ContextMenuItem(
          icon: Icons.delete_outline_rounded,
          label: 'Delete channel',
          isDangerous: true,
          onTap: () => _delete(context),
        ),
      ],
    );
  }
}
