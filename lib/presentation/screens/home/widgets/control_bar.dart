import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../theme/custom_colors.dart';
import 'screen_share_settings_dialog.dart';

/// Floating control bar shown at the bottom of the video area.
class ControlBar extends StatelessWidget {
  final Room room;
  final VoidCallback onLeave;

  const ControlBar({super.key, required this.room, required this.onLeave});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppCubit, AppState>(
      builder: (context, state) {
        final localParticipant = room.localParticipant;
        final isMicEnabled = localParticipant?.isMicrophoneEnabled() ?? false;
        final isCameraEnabled = localParticipant?.isCameraEnabled() ?? false;
        final isScreenSharing =
            localParticipant?.isScreenShareEnabled() ?? false;

        return Positioned(
          bottom: 32,
          left: 0,
          right: 0,
          child: Center(
            child: _ControlBarContent(
              room: room,
              isMicEnabled: isMicEnabled,
              isCameraEnabled: isCameraEnabled,
              isScreenSharing: isScreenSharing,
              onLeave: onLeave,
            ),
          ),
        );
      },
    );
  }
}

class _ControlBarContent extends StatelessWidget {
  final Room room;
  final bool isMicEnabled;
  final bool isCameraEnabled;
  final bool isScreenSharing;
  final VoidCallback onLeave;

  const _ControlBarContent({
    required this.room,
    required this.isMicEnabled,
    required this.isCameraEnabled,
    required this.isScreenSharing,
    required this.onLeave,
  });

  Future<void> _handleScreenShare(BuildContext context) async {
    if (isScreenSharing) {
      await room.localParticipant?.setScreenShareEnabled(false);
      return;
    }

    final settings = await showDialog<dynamic>(
      context: context,
      builder: (_) => const ScreenShareSettingsDialog(),
    );
    if (settings == null) return;

    try {
      await room.localParticipant?.setScreenShareEnabled(
        true,
        screenShareCaptureOptions: ScreenShareCaptureOptions(
          useiOSBroadcastExtension: false,
        ),
      );
    } catch (e) {
      debugPrint('Screen share failed: $e');
    }
  }

  Future<void> _toggleMic(BuildContext context) async {
    final next = !isMicEnabled;
    await room.localParticipant?.setMicrophoneEnabled(next);
    context.read<AppCubit>().setAudioEnabled(next);
  }

  Future<void> _toggleCamera(BuildContext context) async {
    final next = !isCameraEnabled;
    await room.localParticipant?.setCameraEnabled(next);
    context.read<AppCubit>().setVideoEnabled(next);
  }

  Future<void> _leave(BuildContext context) async {
    await room.disconnect();
    onLeave();
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.read<ThemeCubit>().state;
    final bgColor = themeState.isDarkTheme
        ? const Color(0xFF1E1E21)
        : CustomColors.bgSecondaryLight;
    final borderColor = themeState.borderPrimary;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bgColor.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: themeState.isDarkTheme ? 0.4 : 0.1,
            ),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Screen share
          _ControlButton(
            icon: isScreenSharing
                ? Icons.monitor_outlined
                : Icons.present_to_all,
            isActive: isScreenSharing,
            tooltip: isScreenSharing ? 'Stop sharing' : 'Share screen',
            onTap: () => _handleScreenShare(context),
          ),
          const SizedBox(width: 4),
          // Camera
          _ControlButton(
            icon: isCameraEnabled ? Icons.videocam : Icons.videocam_off,
            isDimmed: !isCameraEnabled,
            tooltip: isCameraEnabled ? 'Turn off camera' : 'Turn on camera',
            onTap: () => _toggleCamera(context),
          ),
          const SizedBox(width: 4),
          // Mic
          _ControlButton(
            icon: isMicEnabled ? Icons.mic : Icons.mic_off,
            isError: !isMicEnabled,
            tooltip: isMicEnabled ? 'Mute' : 'Unmute',
            onTap: () => _toggleMic(context),
          ),
          // Divider
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 10),
            width: 1,
            height: 32,
            color: borderColor,
          ),
          // Leave
          Material(
            color: CustomColors.error,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _leave(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                child: Row(
                  children: const [
                    Icon(Icons.call_end, size: 20, color: Colors.white),
                    SizedBox(width: 8),
                    Text(
                      'Leave',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final bool isDimmed;
  final bool isError;
  final String tooltip;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.isActive = false,
    this.isDimmed = false,
    this.isError = false,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.read<ThemeCubit>().state;

    Color bgColor = Colors.transparent;
    Color iconColor;

    if (isActive) {
      bgColor = CustomColors.primary.withValues(alpha: 0.15);
      iconColor = CustomColors.primary;
    } else if (isError) {
      bgColor = CustomColors.error.withValues(alpha: 0.1);
      iconColor = CustomColors.error;
    } else if (isDimmed) {
      bgColor = themeState.bgTertiary;
      iconColor = themeState.textTertiary;
    } else {
      iconColor = themeState.textSecondary;
    }

    return Tooltip(
      message: tooltip,
      child: Material(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          hoverColor: themeState.bgHover,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Icon(icon, size: 22, color: iconColor),
          ),
        ),
      ),
    );
  }
}
