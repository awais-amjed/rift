import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:toastification/toastification.dart';

import '../../../../data/classes/screen_share_settings.dart';
import '../../../../data/classes/server_limits.dart';
import '../../../../data/constants.dart';
import '../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../logic/cubits/screenshare/screenshare_cubit.dart';
import '../../../../logic/cubits/server/server_cubit.dart';
import '../../../../logic/cubits/sound_share/sound_share_cubit.dart';
import '../../../../logic/helper_methods.dart';
import '../../../../logic/services/host_platform.dart';
import '../../../../src/rust/api/screenshare/types.dart';
import '../../../common/app_modal.dart';
import '../../../responsive/shell_scope.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_shadows.dart';
import '../../../theme/app_text.dart';
import '../../../theme/custom_colors.dart';
import '../../../theme/theme_context.dart';
import '../screenshare/screen_share_settings_dialog.dart';
import '../soundboard/soundboard_button.dart';
import '../soundshare/sound_share_picker_dialog.dart';
import 'widgets/control_button.dart';

/// Over the widget budget and one job: the call's controls, and what pressing
/// each one does — screen share, sound share and deafen each need a few steps.
///
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
          prev.isServerDeafened != curr.isServerDeafened,
      builder: (context, livekitState) {
        return BlocBuilder<ScreenshareCubit, ScreenshareState>(
          buildWhen: (prev, curr) => prev.isSharing != curr.isSharing,
          builder: (context, screenshareState) {
            return BlocBuilder<SoundShareCubit, SoundShareState>(
              buildWhen: (prev, curr) => prev.isSharing != curr.isSharing,
              builder: (context, soundShareState) {
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
                            // The effective state, not the raw toggles: a
                            // moderator holding the mic has to read as muted here.
                            isMicOn: livekitState.isMicOn,
                            isCameraEnabled: livekitState.isCameraEnabled,
                            isScreenSharing: screenshareState.isSharing,
                            isSharingSound: soundShareState.isSharing,
                            isDeafened: livekitState.isDeafenedEffective,
                            isServerMuted: livekitState.isServerMuted,
                            isServerDeafened: livekitState.isServerDeafened,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _ControlBarContent extends StatelessWidget {
  final bool isMicOn;
  final bool isCameraEnabled;
  final bool isScreenSharing;
  final bool isSharingSound;
  final bool isDeafened;

  /// Moderation, so the tooltip can say why the button won't move.
  final bool isServerMuted;
  final bool isServerDeafened;

  const _ControlBarContent({
    required this.isMicOn,
    required this.isServerMuted,
    required this.isServerDeafened,
    required this.isCameraEnabled,
    required this.isScreenSharing,
    required this.isSharingSound,
    required this.isDeafened,
  });

  Future<void> _handleScreenShare(BuildContext context) async {
    final screenshareCubit = context.read<ScreenshareCubit>();
    final livekitCubit = context.read<LiveKitCubit>();
    final serverCubit = context.read<ServerCubit>();

    if (screenshareCubit.state.isSharing) {
      await screenshareCubit.stopScreenShare();
      return;
    }

    // The settings dialog is a *desktop* capture dialog — capture type,
    // window list, bitrate, codec, system-audio toggle. None of it exists
    // where the SDK does the capturing: a browser shows its own picker, and
    // Android shows the MediaProjection consent sheet, which is the picker.
    // Putting ours in front of either would be asking twice, the first time
    // about things that cannot be chosen.
    final ScreenShareSettings settings;
    if (kIsWeb || HostPlatform.isMobile) {
      settings = const ScreenShareSettings();
    } else {
      // The picker is told what this server allows so it can grey out what it
      // will not carry. The clamp in [ScreenshareCubit] still applies — web
      // and mobile never open this dialog at all — but a control that offers
      // a number and then quietly uses a different one is the wrong control.
      final dialogSettings = await showCustomDialog<ScreenShareSettings>(
        context: context,
        build: (_) => ScreenShareSettingsDialog(
          maxShareMbps:
              serverCubit.state.selectedServer?.limits.maxShareMbps ??
              ServerLimits.unlimited,
        ),
      );
      if (dialogSettings == null) return;
      settings = dialogSettings;
    }

    if (livekitCubit.state.currentChannelId == null) return;

    await screenshareCubit.startScreenShare(settings: settings);
  }

  /// Shares one application's sound, with no picture — a room listening to
  /// music somebody has on, rather than watching them have it on.
  Future<void> _handleSoundShare(BuildContext context) async {
    final soundShareCubit = context.read<SoundShareCubit>();
    final livekitCubit = context.read<LiveKitCubit>();

    if (soundShareCubit.state.isSharing) {
      await soundShareCubit.stopSoundShare();
      return;
    }

    final source = await showCustomDialog<AudioSource>(
      context: context,
      build: (_) => const SoundSharePickerDialog(),
    );
    if (source == null) return;
    if (livekitCubit.state.currentChannelId == null) return;

    await soundShareCubit.startSoundShare(source: source);
  }

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

  Future<void> _leave(BuildContext context) async {
    await context.read<LiveKitCubit>().disconnect();
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    final bgColor = themeState.bgElevated;
    final compact = context.layoutMode.isCompact;

    final radius = BorderRadius.circular(K.radiusCard);

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
                // Sound share. Desktop only: capturing another
                // application's output is something a phone and a browser
                // tab cannot do at all, so there is no button rather than
                // a button that explains itself.
                if (SoundShareCubit.isSupported) ...[
                  ControlButton(
                    icon: isSharingSound
                        ? Icons.music_note_rounded
                        : Icons.music_note_outlined,
                    isActive: isSharingSound,
                    tooltip: isSharingSound
                        ? 'Stop sharing sound'
                        : 'Share sound',
                    onTap: () => _handleSoundShare(context),
                  ),
                  const SizedBox(width: 4),
                ],
                // Screen share
                ControlButton(
                  icon: isScreenSharing
                      ? Icons.monitor_outlined
                      : Icons.present_to_all,
                  isActive: isScreenSharing,
                  tooltip: isScreenSharing ? 'Stop sharing' : 'Share screen',
                  onTap: () => _handleScreenShare(context),
                ),
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
                // Leave
                Material(
                  color: CustomColors.error,
                  borderRadius: BorderRadius.circular(K.radiusRow),
                  child: InkWell(
                    mouseCursor: WidgetStateMouseCursor.clickable,
                    borderRadius: BorderRadius.circular(K.radiusRow),
                    // Opaque, so hovering deepens the red rather than
                    // washing it — the one control here you can't undo.
                    hoverColor: CustomColors.errorDark,
                    onTap: () => _leave(context),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 12 : 20,
                        vertical: 12,
                      ),
                      child: Row(
                        spacing: 8,
                        children: [
                          const Icon(
                            Icons.call_end,
                            size: 19,
                            color: CustomColors.onError,
                          ),
                          // The word goes on a phone. The pill is a
                          // min-width row of five fixed controls and no
                          // flex, so anything it cannot fit it overflows
                          // — and the red circle-with-a-handset is not a
                          // symbol anyone needs the caption for.
                          if (!compact)
                            Text(
                              'Leave',
                              style: AppText.row.copyWith(
                                fontWeight: FontWeight.w700,
                                color: CustomColors.onError,
                              ),
                            ),
                        ],
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
