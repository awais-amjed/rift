import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/services/call_duration.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/custom_colors.dart';
import '../../../../theme/theme_context.dart';
import '../mobile_shell_scope.dart';

/// Over the widget budget and one job: the call kept a tap away on a phone.
///
/// The call you are in, kept one tap away from every other screen on a phone.
///
/// A desktop keeps the call in a pane beside whatever you are reading, so it
/// has nothing like this. A phone pushes the call as a page and lets you leave
/// the page without leaving the call — which would leave you in a call you
/// can no longer see, unable to mute. So this sits over the list and above
/// every composer: the channel, how long, your mic, and Leave, with the rest
/// of the bar taking you back in.
///
/// Draws nothing outside the phone shell, outside a call, or while the call
/// page itself is on top.
class MiniCallBar extends StatelessWidget {
  const MiniCallBar({super.key});

  @override
  Widget build(BuildContext context) {
    final shell = MobileShellScope.maybeOf(context);
    if (shell == null || shell.callOnTop) return const SizedBox.shrink();

    return BlocBuilder<LiveKitCubit, LiveKitState>(
      buildWhen: (a, b) =>
          a.connectionState != b.connectionState ||
          a.currentChannelId != b.currentChannelId ||
          a.isMicOn != b.isMicOn ||
          a.connectedAt != b.connectedAt,
      builder: (context, call) {
        final channelId = call.currentChannelId;
        if (channelId == null ||
            call.connectionState == LiveKitConnectionState.disconnected) {
          return const SizedBox.shrink();
        }
        final name = context.select<ServerCubit, String>(
          (c) =>
              c.state.selectedServer?.channels
                  .where((ch) => ch.id == channelId)
                  .map((ch) => ch.name)
                  .firstOrNull ??
              'Voice',
        );
        return _Bar(
          channelName: name,
          failed: call.connectionState == LiveKitConnectionState.error,
          connectedAt: call.connectedAt,
          micOn: call.isMicOn,
          onOpen: shell.openCall,
        );
      },
    );
  }
}

class _Bar extends StatefulWidget {
  final String channelName;
  final bool failed;
  final DateTime? connectedAt;
  final bool micOn;
  final VoidCallback onOpen;

  const _Bar({
    required this.channelName,
    required this.failed,
    required this.connectedAt,
    required this.micOn,
    required this.onOpen,
  });

  @override
  State<_Bar> createState() => _BarState();
}

class _BarState extends State<_Bar> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final at = widget.connectedAt;
    // Until the room is up there is no length to give, only that it is on
    // its way.
    final status = widget.failed
        ? 'Couldn\'t connect · tap to see why'
        : at == null
        ? 'Connecting…'
        : '${formatCallDuration(DateTime.now().difference(at))} · tap to return';
    final radius = BorderRadius.circular(K.radiusCard);

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: Material(
        color: theme.bgElevated,
        borderRadius: radius,
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          borderRadius: radius,
          onTap: widget.onOpen,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: theme.borderElevated),
            ),
            child: Row(
              spacing: 10,
              children: [
                Icon(
                  Icons.graphic_eq_rounded,
                  size: K.iconButton,
                  color: context.theme.statusInk(CustomColors.success),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.channelName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.strong.copyWith(
                          color: theme.textPrimary,
                        ),
                      ),
                      Text(
                        status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.figure.copyWith(
                          color: theme.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox.square(
                  dimension: K.touchTargetMin,
                  child: IconButton(
                    tooltip: widget.micOn ? 'Mute' : 'Unmute',
                    onPressed: () =>
                        context.read<LiveKitCubit>().toggleMicrophone(),
                    icon: Icon(
                      widget.micOn ? Icons.mic_none_rounded : Icons.mic_off,
                      size: K.iconLarge,
                      color: widget.micOn
                          ? theme.textSecondary
                          : CustomColors.error,
                    ),
                  ),
                ),
                SizedBox.square(
                  dimension: K.touchTargetMin,
                  child: Material(
                    color: CustomColors.error,
                    borderRadius: BorderRadius.circular(K.radiusRow),
                    child: InkWell(
                      mouseCursor: WidgetStateMouseCursor.clickable,
                      borderRadius: BorderRadius.circular(K.radiusRow),
                      onTap: () => context.read<LiveKitCubit>().disconnect(),
                      child: const Tooltip(
                        message: 'Leave call',
                        child: Icon(
                          Icons.call_end,
                          size: K.iconLarge,
                          color: CustomColors.onError,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
