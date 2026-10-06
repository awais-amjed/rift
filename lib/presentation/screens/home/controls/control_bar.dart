import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:toastification/toastification.dart';

import '../../../../data/constants.dart';
import '../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../logic/cubits/sound_share/sound_share_cubit.dart';
import '../../../../logic/helper_methods.dart';
import '../../../responsive/shell_scope.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_shadows.dart';
import '../../../theme/theme_context.dart';
import '../soundboard/soundboard_button.dart';
import 'screen_share/screen_share_control.dart';
import 'widgets/control_button.dart';
import 'widgets/leave_button.dart';
import 'widgets/sound_share_button.dart';

/// Floating control bar shown at the bottom of the video area.
///
/// Visibility is driven by the parent ([RoomView]) so it fades in lockstep
/// with the context strip — together they form focus mode: idle in a call and
/// the chrome fades, leaving the video edge-to-edge.
class ControlBar extends StatelessWidget {
  final bool visible;

  const ControlBar({super.key, required this.visible});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LiveKitCubit, LiveKitState>(
      // The toggles, not the room: every speaking change emits a new state.
      buildWhen: (prev, curr) =>
          prev.isMicOn != curr.isMicOn ||
          prev.isCameraEnabled != curr.isCameraEnabled ||
          prev.isDeafenedEffective != curr.isDeafenedEffective ||
          prev.isServerMuted != curr.isServerMuted ||
          prev.isServerDeafened != curr.isServerDeafened ||
          prev.subscribedScreenshares.isEmpty !=
              curr.subscribedScreenshares.isEmpty,
      builder: (context, livekitState) {
        return Positioned(
          bottom: K.callBarOffset,
          left: 0,
          right: 0,
          child: Center(
            child: AnimatedOpacity(
              opacity: visible ? 1.0 : 0.0,
              duration: AppMotion.enter,
              child: AnimatedSlide(
                offset: visible ? Offset.zero : const Offset(0, 0.4),
                duration: AppMotion.enter,
                curve: Curves.easeInOut,
                child: IgnorePointer(
                  ignoring: !visible,
                  child: _ControlBarContent(
                    // The effective state, not the raw toggles: a moderator
                    // holding the mic has to read as muted here.
                    isMicOn: livekitState.isMicOn,
                    isCameraEnabled: livekitState.isCameraEnabled,
                    isDeafened: livekitState.isDeafenedEffective,
                    isServerMuted: livekitState.isServerMuted,
                    isServerDeafened: livekitState.isServerDeafened,
                    isWatching: livekitState.subscribedScreenshares.isNotEmpty,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ControlBarContent extends StatelessWidget {
  final bool isMicOn;
  final bool isCameraEnabled;
  final bool isDeafened;

  /// A stream is open here, so the last control stops watching rather than
  /// leaving — see [LeaveButton].
  final bool isWatching;

  /// Moderation, so the tooltip can say why the button won't move.
  final bool isServerMuted;
  final bool isServerDeafened;

  const _ControlBarContent({
    required this.isMicOn,
    required this.isServerMuted,
    required this.isServerDeafened,
    required this.isCameraEnabled,
    required this.isDeafened,
    required this.isWatching,
  });

  Future<void> _toggleMic(BuildContext context) async {
    final cubit = context.read<LiveKitCubit>();
    if (_announceModeration(cubit)) return;
    await cubit.toggleMicrophone();
  }

  Future<void> _toggleDeafen(BuildContext context) async {
    final cubit = context.read<LiveKitCubit>();
    if (_announceModeration(cubit)) return;
    await cubit.toggleDeafen();
  }

  /// Says why the control won't move, and reports whether it said anything.
  ///
  /// The cubit already refuses these while moderated, and the tooltip already
  /// explains it — but a tooltip needs a pointer to hover, and the platform
  /// where this matters most has none. Without this a moderated phone user
  /// taps mute, sees nothing at all happen, and reasonably concludes the app
  /// is broken.
  bool _announceModeration(LiveKitCubit cubit) {
    final notice = cubit.state.moderationNotice;
    if (notice == null) return false;
    HelperMethods.showToast(
      title: 'Held by a moderator',
      description: notice,
      type: ToastificationType.warning,
    );
    return true;
  }

  Future<void> _toggleCamera(BuildContext context) async {
    await context.read<LiveKitCubit>().toggleCamera();
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    final bgColor = themeState.bgElevated;
    final compact = context.layoutMode.isCompact;

    final radius = BorderRadius.circular(K.radiusCard);

    // The width the call has, not the window's: a desktop window can be wide
    // while the stage beside the sidebar is narrow, and the pill is a row of
    // fixed controls with no flex. So the word on Leave goes first, and if
    // even the bare pill does not fit it shrinks rather than overflowing.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: K.callBarSideMargin),
      child: LayoutBuilder(
        builder: (context, constraints) => FittedBox(
          fit: BoxFit.scaleDown,
          child: _pill(
            context,
            bgColor,
            radius,
            compact: compact,
            showLabel: !compact && constraints.maxWidth >= K.callBarLabelWidth,
          ),
        ),
      ),
    );
  }

  Widget _pill(
    BuildContext context,
    Color bgColor,
    BorderRadius radius, {
    required bool compact,
    required bool showLabel,
  }) {
    final themeState = context.theme;
    // Glass, not a slab: the pill floats over live video, so it blurs
    // what's behind it rather than hiding it. The shadow sits outside the
    // clip — inside, the clip would eat it.
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: AppShadows.voicePill,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: bgColor.withValues(alpha: 0.9),
              borderRadius: radius,
              border: Border.all(color: themeState.borderElevated),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // The soundboard, first because it is the one control
                // here that is not about this person's own microphone or
                // screen — it is the room's.
                const SoundboardButton(),
                if (SoundShareCubit.isSupported) ...[
                  const SoundShareButton(),
                  const SizedBox(width: 4),
                ],
                const ScreenShareControl(),
                const SizedBox(width: 4),
                // Camera
                ControlButton(
                  icon: isCameraEnabled ? Icons.videocam : Icons.videocam_off,
                  isDimmed: !isCameraEnabled,
                  tooltip: isCameraEnabled
                      ? 'Turn off camera'
                      : 'Turn on camera',
                  onTap: () => _toggleCamera(context),
                ),
                const SizedBox(width: 4),
                // Mic
                ControlButton(
                  icon: isMicOn ? Icons.mic : Icons.mic_off,
                  isError: !isMicOn,
                  tooltip: isServerMuted || isServerDeafened
                      ? 'Muted by a moderator'
                      : (isMicOn ? 'Mute' : 'Unmute'),
                  onTap: () => _toggleMic(context),
                ),
                const SizedBox(width: 4),
                // Deafen
                ControlButton(
                  icon: isDeafened ? Icons.headset_off : Icons.headset,
                  isError: isDeafened,
                  tooltip: isServerDeafened
                      ? 'Deafened by a moderator'
                      : (isDeafened ? 'Undeafen' : 'Deafen'),
                  onTap: () => _toggleDeafen(context),
                ),
                // Divider
                Container(
                  margin: EdgeInsets.symmetric(horizontal: compact ? 6 : 10),
                  width: 1,
                  height: 30,
                  color: themeState.borderElevated,
                ),
                LeaveButton(
                  watching: isWatching,
                  compact: compact,
                  showLabel: showLabel,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
