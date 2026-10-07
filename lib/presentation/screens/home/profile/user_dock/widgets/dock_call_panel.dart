import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/constants.dart';
import '../../../../../../data/enums/home_surface.dart';
import '../../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../../logic/cubits/channel_chat/channel_chat_cubit.dart';
import '../../../../../../logic/cubits/dm_call/dm_call_cubit.dart';
import '../../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../common/calls/call_clock.dart';
import '../../../../../theme/app_motion.dart';
import '../../../../../theme/app_text.dart';
import '../../../../../theme/custom_colors.dart';
import '../../../../../theme/theme_context.dart';
import '../../../calls/open_call_conversation.dart';
import 'dock_call_controls.dart';

/// The call you are in, at the top of the user dock: where it is, how long,
/// Leave, and the call bar's controls — so a call can be run from the
/// sidebar while the centre shows a chat.
///
/// Grows the dock upwards when a call starts and folds away when it ends.
/// The content stays put against the dock's own row while the top edge
/// travels, so it reads as the dock opening rather than a panel dropping in.
class DockCallPanel extends StatelessWidget {
  const DockCallPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LiveKitCubit, LiveKitState>(
      // What the panel draws, not the room: every speaking change emits.
      buildWhen: (a, b) =>
          a.connectionState != b.connectionState ||
          a.currentChannelId != b.currentChannelId ||
          a.dmCall != b.dmCall ||
          a.connectedAt != b.connectedAt ||
          a.isCameraEnabled != b.isCameraEnabled,
      builder: (context, call) {
        final shown =
            call.inCall &&
            call.connectionState != LiveKitConnectionState.disconnected;
        return AnimatedSwitcher(
          duration: AppMotion.enter,
          switchInCurve: AppMotion.arrive,
          switchOutCurve: AppMotion.arrive,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SizeTransition(
              sizeFactor: animation,
              alignment: Alignment.bottomCenter,
              child: child,
            ),
          ),
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.bottomCenter,
            children: [...previous, ?current],
          ),
          // One key for every call, so moving to another channel changes the
          // words in place rather than folding the panel and opening it again.
          child: shown
              ? _CallSection(key: const ValueKey('call'), call: call)
              : const SizedBox(width: double.infinity),
        );
      },
    );
  }
}

class _CallSection extends StatefulWidget {
  final LiveKitState call;

  const _CallSection({super.key, required this.call});

  @override
  State<_CallSection> createState() => _CallSectionState();
}

class _CallSectionState extends State<_CallSection> {
  /// Puts the call in the centre: a DM call's conversation, or a channel's
  /// stage on its own server, with any chat over it closed.
  void _open() {
    final dm = widget.call.dmCall;
    if (dm != null) {
      final row = context.read<DmCallCubit>().state.active?.call;
      if (row == null) return;
      unawaited(
        openCallConversation(context, serverId: dm.serverId, call: row),
      );
      return;
    }
    final channelId = widget.call.currentChannelId;
    final servers = context.read<ServerCubit>();
    final home = servers.state.servers
        .where((s) => s.channels.any((c) => c.id == channelId))
        .firstOrNull;
    if (home != null && servers.state.selectedServer?.id != home.id) {
      servers.selectServer(home);
    }
    context.read<AppCubit>().setSurface(HomeSurface.server);
    unawaited(context.read<ChannelChatCubit>().closeChannel());
  }

  void _leave() {
    if (widget.call.dmCall != null) {
      unawaited(context.read<DmCallCubit>().hangUp());
    } else {
      unawaited(context.read<LiveKitCubit>().disconnect());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final call = widget.call;
    final channelId = call.currentChannelId;
    // Looked up on every server: the call stays on while you read another.
    final place = context.select<ServerCubit, (String, String)?>((c) {
      for (final server in c.state.servers) {
        for (final channel in server.channels) {
          if (channel.id == channelId) return (channel.name, server.name);
        }
      }
      return null;
    });
    final dm = call.dmCall;
    final name = dm?.peerName ?? place?.$1 ?? 'Voice';
    final where = dm != null ? 'Direct call' : place?.$2;

    final at = call.connectedAt;
    final failed = call.connectionState == LiveKitConnectionState.error;
    final quiet = AppText.meta.copyWith(color: theme.textTertiary);
    // Mono while it ticks, so the line does not shift as the digits roll
    // over. The clock ticks itself; this card rebuilds only when the call
    // changes.
    final status = failed
        ? Text('Couldn\'t connect', style: quiet)
        : at == null
        ? Text('Connecting…', style: quiet)
        : CallClock(
            since: at,
            style: AppText.figure.copyWith(color: theme.textTertiary),
          );
    final radius = BorderRadius.circular(K.radiusRow);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          spacing: 6,
          children: [
            Expanded(
              child: Material(
                color: Colors.transparent,
                borderRadius: radius,
                child: InkWell(
                  mouseCursor: WidgetStateMouseCursor.clickable,
                  borderRadius: radius,
                  hoverColor: theme.bgActive,
                  onTap: _open,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    child: Row(
                      spacing: 8,
                      children: [
                        Icon(
                          failed
                              ? Icons.error_outline_rounded
                              : Icons.graphic_eq_rounded,
                          size: K.iconButton,
                          color: theme.statusInk(
                            failed ? CustomColors.error : CustomColors.success,
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.strong.copyWith(
                                  color: theme.textPrimary,
                                ),
                              ),
                              Row(
                                children: [
                                  status,
                                  if (where != null)
                                    Flexible(
                                      child: Text(
                                        ' · $where',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: quiet,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            _LeaveButton(direct: dm != null, onTap: _leave),
          ],
        ),
        const SizedBox(height: 8),
        DockCallControls(cameraOn: call.isCameraEnabled),
        Container(
          height: 1,
          margin: const EdgeInsets.symmetric(vertical: 8),
          color: theme.borderElevated,
        ),
      ],
    );
  }
}

/// Leave, red like the call bar's: the one control here that ends something.
class _LeaveButton extends StatelessWidget {
  final bool direct;
  final VoidCallback onTap;

  const _LeaveButton({required this.direct, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(K.radiusRow);
    return Tooltip(
      message: direct ? 'Hang up' : 'Leave call',
      waitDuration: K.tooltipDelay,
      child: Material(
        color: CustomColors.error,
        borderRadius: radius,
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          borderRadius: radius,
          hoverColor: CustomColors.errorDark,
          onTap: onTap,
          child: const SizedBox.square(
            dimension: K.dockCallButtonHeight,
            child: Icon(
              Icons.call_end,
              size: K.iconButton,
              color: CustomColors.onError,
            ),
          ),
        ),
      ),
    );
  }
}
