import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/classes/screen_share_settings.dart';
import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../theme/custom_colors.dart';
import '../../../common/app_button.dart';

/// Dialog for configuring screen share settings (resolution, fps, bitrate, audio).
class ScreenShareSettingsDialog extends StatefulWidget {
  const ScreenShareSettingsDialog({super.key});

  @override
  State<ScreenShareSettingsDialog> createState() =>
      _ScreenShareSettingsDialogState();
}

class _ScreenShareSettingsDialogState extends State<ScreenShareSettingsDialog> {
  static const _resolutions = [720, 1080, 1440, 2160];
  static const _fpsOptions = [30, 60];
  static const _bitrateOptions = [2, 4, 6, 8, 10, 12, 14, 15];
  static const _resolutionLabels = {
    720: '720p',
    1080: '1080p',
    1440: '2K',
    2160: '4K',
  };

  late int _resolution;
  late int _fps;
  late int _bitrate;
  late bool _shareAudio;

  @override
  void initState() {
    super.initState();
    final settings = context.read<AppCubit>().state.screenShareSettings;
    _resolution = settings.resolution;
    _fps = settings.fps;
    _bitrate = settings.bitrate;
    _shareAudio = settings.shareAudio;
  }

  void _confirm() {
    final settings = ScreenShareSettings(
      resolution: _resolution,
      fps: _fps,
      bitrate: _bitrate,
      shareAudio: _shareAudio,
    );
    context.read<AppCubit>().setScreenShareSettings(settings);
    Navigator.of(context).pop(settings);
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.read<ThemeCubit>().state;
    final bgColor = themeState.isDarkTheme
        ? const Color(0xFF1E1E21)
        : CustomColors.bgSecondaryLight;
    final borderColor = themeState.borderPrimary;
    final textPrimary = themeState.textPrimary;
    final textSecondary = themeState.textSecondary;
    final textQuaternary = themeState.textQuaternary;

    return Dialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: borderColor),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: CustomColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.monitor,
                      size: 18,
                      color: CustomColors.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Screen Share Settings',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: textPrimary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, size: 18, color: textQuaternary),
                    style: IconButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
              Divider(height: 24, color: borderColor),
              // Resolution
              _Section(
                label: 'Resolution',
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _resolutions
                        .map(
                          (r) => _Chip(
                            label: _resolutionLabels[r] ?? '${r}p',
                            active: _resolution == r,
                            onTap: () => setState(() => _resolution = r),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // FPS
              _Section(
                label: 'Frame Rate',
                children: [
                  Wrap(
                    spacing: 8,
                    children: _fpsOptions
                        .map(
                          (f) => _Chip(
                            label: '$f fps',
                            active: _fps == f,
                            onTap: () => setState(() => _fps = f),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Bitrate
              _Section(
                label: 'Bitrate',
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _bitrateOptions
                        .map(
                          (b) => _Chip(
                            label: '$b Mbps',
                            active: _bitrate == b,
                            onTap: () => setState(() => _bitrate = b),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Share audio toggle
              GestureDetector(
                onTap: () => setState(() => _shareAudio = !_shareAudio),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: _shareAudio
                        ? CustomColors.primary.withValues(alpha: 0.08)
                        : themeState.bgTertiary,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _shareAudio
                          ? CustomColors.primary.withValues(alpha: 0.35)
                          : borderColor,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _shareAudio ? Icons.volume_up : Icons.volume_off,
                        size: 17,
                        color: _shareAudio
                            ? CustomColors.primary
                            : textQuaternary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Share Audio',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: _shareAudio
                                    ? textPrimary
                                    : textSecondary,
                              ),
                            ),
                            Text(
                              _shareAudio
                                  ? 'System audio will be captured'
                                  : 'No audio will be shared',
                              style: TextStyle(
                                fontSize: 11,
                                color: textQuaternary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Toggle pill
                      _TogglePill(active: _shareAudio),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Summary
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: themeState.bgTertiary,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: borderColor),
                ),
                child: Center(
                  child: RichText(
                    text: TextSpan(
                      style: TextStyle(fontSize: 13, color: textSecondary),
                      children: [
                        const TextSpan(text: 'Up to '),
                        TextSpan(
                          text: '${_resolutionLabels[_resolution]}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const TextSpan(text: ' · '),
                        TextSpan(
                          text: '$_fps fps',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const TextSpan(text: ' · '),
                        TextSpan(
                          text: '$_bitrate Mbps',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const TextSpan(text: ' · '),
                        TextSpan(
                          text: _shareAudio ? 'Audio on' : 'Audio off',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: _shareAudio
                                ? CustomColors.primary
                                : textQuaternary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppButton(
                    label: 'Cancel',
                    variant: AppButtonVariant.secondary,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 10),
                  AppButton(label: 'Start Sharing', onPressed: _confirm),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String label;
  final List<Widget> children;

  const _Section({required this.label, required this.children});

  @override
  Widget build(BuildContext context) {
    final textTertiary = context.read<ThemeCubit>().state.textTertiary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: textTertiary,
          ),
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _Chip({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final themeState = context.read<ThemeCubit>().state;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? CustomColors.primary : themeState.bgTertiary,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? CustomColors.primary : themeState.borderPrimary,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: active ? Colors.white : themeState.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _TogglePill extends StatelessWidget {
  final bool active;

  const _TogglePill({required this.active});

  @override
  Widget build(BuildContext context) {
    final bgActive = context.read<ThemeCubit>().state.bgActive;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 40,
      height: 22,
      decoration: BoxDecoration(
        color: active ? CustomColors.primary : bgActive,
        borderRadius: BorderRadius.circular(11),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 150),
        alignment: active ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          width: 18,
          height: 18,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(blurRadius: 2, color: Colors.black26)],
          ),
        ),
      ),
    );
  }
}
