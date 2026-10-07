import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/constants.dart';
import '../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../theme/app_text.dart';
import '../../theme/custom_colors.dart';
import '../../theme/theme_context.dart';
import 'call_clock.dart';

/// The call you are in, as one row: what it is, how long it has run, your
/// mic, and Leave — with the rest of the row taking you back to it.
///
/// The phone's [MiniCallBar], which keeps any call a tap away. A desktop has
/// the call on top of the user dock instead ([DockCallPanel]).
class CallReturnBar extends StatelessWidget {
  final String channelName;
  final bool failed;
  final DateTime? connectedAt;
  final bool micOn;
  final VoidCallback onOpen;

  /// Ends the call. A channel's is leaving the room; a DM call's is hanging
  /// up, which also tells the other end.
  final VoidCallback onLeave;

  /// Says how to get back after the time. Off in a desktop sidebar, where
  /// the row is too narrow for it and a pointer shows it is pressable.
  final bool showHint;

  const CallReturnBar({
    super.key,
    required this.channelName,
    required this.failed,
    required this.connectedAt,
    required this.micOn,
    required this.onOpen,
    required this.onLeave,
    this.showHint = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final at = connectedAt;
    // Until the room is up there is no length to give, only that it is on
    // its way.
    final statusStyle = AppText.figure.copyWith(color: theme.textTertiary);
    final radius = BorderRadius.circular(K.radiusCard);

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: Material(
        color: theme.bgElevated,
        borderRadius: radius,
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          borderRadius: radius,
          onTap: onOpen,
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
                        channelName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.strong.copyWith(
                          color: theme.textPrimary,
                        ),
                      ),
                      if (failed || at == null)
                        Text(
                          failed
                              ? 'Couldn\'t connect · tap to see why'
                              : 'Connecting…',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: statusStyle,
                        )
                      else
                        CallClock(
                          since: at,
                          suffix: showHint ? ' · tap to return' : '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: statusStyle,
                        ),
                    ],
                  ),
                ),
                SizedBox.square(
                  dimension: K.touchTargetMin,
                  child: IconButton(
                    tooltip: micOn ? 'Mute' : 'Unmute',
                    onPressed: () =>
                        context.read<LiveKitCubit>().toggleMicrophone(),
                    icon: Icon(
                      micOn ? Icons.mic_none_rounded : Icons.mic_off,
                      size: K.iconLarge,
                      color: micOn ? theme.textSecondary : CustomColors.error,
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
                      onTap: onLeave,
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
