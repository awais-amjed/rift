import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../theme/custom_colors.dart';
import '../screen_share_settings_dialog.dart';

/// Floating control bar shown at the bottom of the video area.
class ControlBar extends StatelessWidget {
  final VoidCallback onLeave;

  const ControlBar({super.key, required this.onLeave});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LiveKitCubit, LiveKitState>(
      builder: (context, state) {
        return Positioned(
          bottom: 32,
          left: 0,
          right: 0,
          child: Center(
            child: _ControlBarContent(
              isMicEnabled: state.isMicEnabled,
              isCameraEnabled: state.isCameraEnabled,
              isScreenSharing: state.isScreenSharing,
              onLeave: onLeave,
            ),
          ),
        );
      },
    );
  }
}

class _ControlBarContent extends StatelessWidget {
  final bool isMicEnabled;
  final bool isCameraEnabled;
  final bool isScreenSharing;
  final VoidCallback onLeave;

  const _ControlBarContent({
    required this.isMicEnabled,
    required this.isCameraEnabled,
    required this.isScreenSharing,
    required this.onLeave,
  });

  Future<void> _handleScreenShare(BuildContext context) async {
    final livekitCubit = context.read<LiveKitCubit>();

    if (isScreenSharing) {
      await livekitCubit.toggleScreenShare();
      return;
    }

    final settings = await showDialog<dynamic>(
      context: context,
      builder: (_) => const ScreenShareSettingsDialog(),
    );
    if (settings == null) return;

    try {
      await livekitCubit.toggleScreenShare();
    } catch (e) {
      debugPrint('Screen share failed: $e');
    }
  }

  Future<void> _toggleMic(BuildContext context) async {
    await context.read<LiveKitCubit>().toggleMicrophone();
  }

  Future<void> _toggleCamera(BuildContext context) async {
    await context.read<LiveKitCubit>().toggleCamera();
  }

  Future<void> _leave(BuildContext context) async {
    await context.read<LiveKitCubit>().disconnect();
    onLeave();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        final bgColor = themeState.isDarkTheme
            ? const Color(0xFF1E1E21)
            : CustomColors.bgSecondaryLight;

        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: bgColor.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: themeState.borderPrimary),
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
                color: themeState.borderPrimary,
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
      },
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
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
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
      },
    );
  }
}
