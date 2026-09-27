import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/constants.dart';
import '../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../logic/services/call_duration.dart';
import '../../theme/app_text.dart';
import '../../theme/custom_colors.dart';
import '../../theme/theme_context.dart';

/// The call you are in, as one row: what it is, how long it has run, your
/// mic, and Leave — with the rest of the row taking you back to it.
///
/// Shared by the phone's [MiniCallBar], which keeps any call a tap away, and
/// the desktop sidebar's bar for a DM call, which lives in a conversation
/// you may have walked away from.
class CallReturnBar extends StatefulWidget {
  final String channelName;
  final bool failed;
  final DateTime? connectedAt;
  final bool micOn;
  final VoidCallback onOpen;

  /// Ends the call. A channel's is leaving the room; a DM call's is hanging
  /// up, which also tells the other end.
  final VoidCallback onLeave;

  const CallReturnBar({
    super.key,
    required this.channelName,
    required this.failed,
    required this.connectedAt,
    required this.micOn,
    required this.onOpen,
    required this.onLeave,
  });

  @override
  State<CallReturnBar> createState() => _CallReturnBarState();
}

class _CallReturnBarState extends State<CallReturnBar> {
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
                      onTap: widget.onLeave,
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
