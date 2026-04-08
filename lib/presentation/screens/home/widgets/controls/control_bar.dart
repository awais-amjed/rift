import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/screen_share_settings.dart';
import '../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../../logic/cubits/screenshare/screenshare_cubit.dart';
import '../../../../common/app_modal.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../theme/custom_colors.dart';
import '../screenshare/screen_share_settings_dialog.dart';

/// Floating control bar shown at the bottom of the video area.
/// Auto-hides after inactivity and reappears when the mouse moves.
class ControlBar extends StatefulWidget {
  const ControlBar({super.key});

  @override
  ControlBarState createState() => ControlBarState();
}

class ControlBarState extends State<ControlBar> {
  static const _hideDelay = Duration(seconds: 2);

  bool _visible = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_hideDelay, () {
      if (mounted) setState(() => _visible = false);
    });
  }

  /// Called by the parent when pointer activity is detected anywhere in the area.
  void onActivity() {
    if (!_visible) setState(() => _visible = true);
    _scheduleHide();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LiveKitCubit, LiveKitState>(
      builder: (context, livekitState) {
        return BlocBuilder<ScreenshareCubit, ScreenshareState>(
          builder: (context, screenshareState) {
            return Positioned(
              bottom: 32,
              left: 0,
              right: 0,
              child: Center(
                child: AnimatedOpacity(
                  opacity: _visible ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: AnimatedSlide(
                    offset: _visible ? Offset.zero : const Offset(0, 0.4),
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    child: IgnorePointer(
                      ignoring: !_visible,
                      child: _ControlBarContent(
                        isMicEnabled: livekitState.isMicEnabled,
                        isCameraEnabled: livekitState.isCameraEnabled,
                        isScreenSharing: screenshareState.isSharing,
                        isDeafened: livekitState.isDeafened,
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
  }
}

class _ControlBarContent extends StatelessWidget {
  final bool isMicEnabled;
  final bool isCameraEnabled;
  final bool isScreenSharing;
  final bool isDeafened;

  const _ControlBarContent({
    required this.isMicEnabled,
    required this.isCameraEnabled,
    required this.isScreenSharing,
    required this.isDeafened,
  });

  Future<void> _handleScreenShare(BuildContext context) async {
    final screenshareCubit = context.read<ScreenshareCubit>();
    final livekitCubit = context.read<LiveKitCubit>();

    // Check if already sharing - if so, stop
    if (screenshareCubit.state.isSharing) {
      await screenshareCubit.stopScreenShare();
      return;
    }

    // On web, skip settings dialog and use default settings
    // The browser will show its own screen selection dialog
    final ScreenShareSettings settings;
    if (kIsWeb) {
      settings = const ScreenShareSettings();
    } else {
      // Show settings dialog on desktop
      final dialogSettings = await showCustomDialog<ScreenShareSettings>(
        context: context,
        builder: (_) => const ScreenShareSettingsDialog(),
      );
      if (dialogSettings == null) return;
      settings = dialogSettings;
    }

    // Guard: must be connected to a channel
    if (livekitCubit.state.currentChannelId == null) {
      debugPrint('No channel connected');
      return;
    }

    try {
      // Server context (URL, token, user info) is resolved by the cubit.
      await screenshareCubit.startScreenShare(settings: settings);
    } catch (e) {
      debugPrint('Screen share failed: $e');
    }
  }

  Future<void> _toggleMic(BuildContext context) async {
    await context.read<LiveKitCubit>().toggleMicrophone();
  }

  Future<void> _toggleDeafen(BuildContext context) async {
    await context.read<LiveKitCubit>().toggleDeafen();
  }

  Future<void> _toggleCamera(BuildContext context) async {
    await context.read<LiveKitCubit>().toggleCamera();
  }

  Future<void> _leave(BuildContext context) async {
    await context.read<LiveKitCubit>().disconnect();
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
                icon: isMicEnabled && !isDeafened ? Icons.mic : Icons.mic_off,
                isError: !isMicEnabled || isDeafened,
                tooltip: isMicEnabled && !isDeafened ? 'Mute' : 'Unmute',
                onTap: () => _toggleMic(context),
              ),
              const SizedBox(width: 4),
              // Deafen
              _ControlButton(
                icon: isDeafened ? Icons.headset_off : Icons.headset,
                isError: isDeafened,
                tooltip: isDeafened ? 'Undeafen' : 'Deafen',
                onTap: () => _toggleDeafen(context),
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
