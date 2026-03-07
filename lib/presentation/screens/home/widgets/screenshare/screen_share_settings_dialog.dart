import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/screen_share_settings.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../theme/custom_colors.dart';
import '../../../../common/app_button.dart';
import 'audio_toggle.dart';
import 'settings_chip.dart';
import 'settings_section.dart';
import 'settings_summary.dart';

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
  late bool _captureFullScreen;

  @override
  void initState() {
    super.initState();
    final settings = context.read<AppCubit>().state.screenShareSettings;
    _resolution = settings.resolution;
    _fps = settings.fps;
    _bitrate = settings.bitrate;
    _shareAudio = settings.shareAudio;
    _captureFullScreen = settings.captureFullScreen;
  }

  void _confirm() {
    final settings = ScreenShareSettings(
      resolution: _resolution,
      fps: _fps,
      bitrate: _bitrate,
      shareAudio: _shareAudio,
      captureFullScreen: _captureFullScreen,
    );
    context.read<AppCubit>().setScreenShareSettings(settings);
    Navigator.of(context).pop(settings);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        final bgColor = themeState.isDarkTheme
            ? const Color(0xFF1E1E21)
            : CustomColors.bgSecondaryLight;

        return Dialog(
          backgroundColor: bgColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: themeState.borderPrimary),
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
                          color: themeState.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(
                          Icons.close,
                          size: 18,
                          color: themeState.textQuaternary,
                        ),
                        style: IconButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Divider(height: 24, color: themeState.borderPrimary),
                  // Capture Type (Full Screen vs Window)
                  SettingsSection(
                    label: 'Capture Type',
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: SettingsChip(
                              label: '🖥️ Full Screen',
                              active: _captureFullScreen,
                              onTap: () =>
                                  setState(() => _captureFullScreen = true),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SettingsChip(
                              label: '🪟 Window',
                              active: !_captureFullScreen,
                              onTap: () =>
                                  setState(() => _captureFullScreen = false),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Resolution
                  SettingsSection(
                    label: 'Resolution',
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _resolutions
                            .map(
                              (r) => SettingsChip(
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
                  SettingsSection(
                    label: 'Frame Rate',
                    children: [
                      Wrap(
                        spacing: 8,
                        children: _fpsOptions
                            .map(
                              (f) => SettingsChip(
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
                  SettingsSection(
                    label: 'Bitrate',
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _bitrateOptions
                            .map(
                              (b) => SettingsChip(
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
                  AudioToggle(
                    shareAudio: _shareAudio,
                    onToggle: () => setState(() => _shareAudio = !_shareAudio),
                  ),
                  const SizedBox(height: 16),
                  // Summary
                  SettingsSummary(
                    captureFullScreen: _captureFullScreen,
                    resolution:
                        _resolutionLabels[_resolution] ?? '${_resolution}p',
                    fps: _fps,
                    bitrate: _bitrate,
                    shareAudio: _shareAudio,
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
      },
    );
  }
}
