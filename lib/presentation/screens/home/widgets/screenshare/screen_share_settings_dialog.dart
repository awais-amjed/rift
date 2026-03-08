import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'dart:io' show Platform;

import '../../../../../data/classes/screen_share_settings.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../src/rust/api/screenshare/audio_linux.dart';
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
  static const _codecOptions = ['VP8', 'H264', 'VP9'];
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
  late String _codec;

  List<AudioSource>? _audioSources;
  AudioSource? _selectedAudioSource;
  bool _loadingAudioSources = false;

  @override
  void initState() {
    super.initState();
    final settings = context.read<AppCubit>().state.screenShareSettings;
    _resolution = settings.resolution;
    _fps = settings.fps;
    _bitrate = settings.bitrate;
    _shareAudio = settings.shareAudio;
    _captureFullScreen = settings.captureFullScreen;
    _codec = settings.codec;
    _selectedAudioSource = settings.selectedAudioSource;

    // Load audio sources on Linux if audio sharing is enabled
    if (Platform.isLinux && _shareAudio) {
      _loadAudioSources();
    }
  }

  Future<void> _loadAudioSources() async {
    setState(() => _loadingAudioSources = true);
    try {
      final sources = await listAudioSources();

      if (mounted) {
        setState(() {
          _audioSources = sources;
          _loadingAudioSources = false;
          // Auto-select first source if none selected
          if (_selectedAudioSource == null && sources.isNotEmpty) {
            _selectedAudioSource = sources.first;
          }
        });
      }
    } catch (e) {
      debugPrint('Failed to load audio sources: $e');
      if (mounted) {
        setState(() => _loadingAudioSources = false);
      }
    }
  }

  void _onAudioToggle() {
    setState(() => _shareAudio = !_shareAudio);
    // Load audio sources when audio is enabled on Linux
    if (Platform.isLinux && _shareAudio && _audioSources == null) {
      _loadAudioSources();
    }
  }

  void _confirm() {
    final settings = ScreenShareSettings(
      resolution: _resolution,
      fps: _fps,
      bitrate: _bitrate,
      shareAudio: _shareAudio,
      captureFullScreen: _captureFullScreen,
      codec: _codec,
      selectedAudioSource: _selectedAudioSource,
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
                  // Codec
                  SettingsSection(
                    label: 'Codec',
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _codecOptions
                            .map(
                              (c) => SettingsChip(
                                label: c,
                                active: _codec == c,
                                onTap: () => setState(() => _codec = c),
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
                    onToggle: _onAudioToggle,
                  ),
                  // Audio source selector (Linux only)
                  if (Platform.isLinux && _shareAudio) ...[
                    const SizedBox(height: 16),
                    SettingsSection(
                      label: 'Audio Source',
                      children: [
                        if (_loadingAudioSources)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          )
                        else if (_audioSources == null ||
                            _audioSources!.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  size: 16,
                                  color: themeState.textTertiary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'No audio sources found. Make sure an application is playing audio.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: themeState.textTertiary,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: _loadAudioSources,
                                  child: const Text('Refresh'),
                                ),
                              ],
                            ),
                          )
                        else
                          Column(
                            children: [
                              for (final source in _audioSources!)
                                InkWell(
                                  onTap: () => setState(
                                    () => _selectedAudioSource = source,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _selectedAudioSource == source
                                          ? CustomColors.primary.withValues(
                                              alpha: 0.12,
                                            )
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: _selectedAudioSource == source
                                            ? CustomColors.primary
                                            : themeState.borderPrimary,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          _selectedAudioSource == source
                                              ? Icons.radio_button_checked
                                              : Icons.radio_button_unchecked,
                                          size: 18,
                                          color: _selectedAudioSource == source
                                              ? CustomColors.primary
                                              : themeState.textTertiary,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                () {
                                                  // Build label: media.name (binary)
                                                  final mainLabel =
                                                      source
                                                          .mediaName
                                                          .isNotEmpty
                                                      ? source.mediaName
                                                      : source
                                                            .appName
                                                            .isNotEmpty
                                                      ? source.appName
                                                      : 'Unknown';

                                                  if (source
                                                      .binary
                                                      .isNotEmpty) {
                                                    return '$mainLabel (${source.binary})';
                                                  }
                                                  return mainLabel;
                                                }(),
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w500,
                                                  color: themeState.textPrimary,
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  // Summary
                  SettingsSummary(
                    captureFullScreen: _captureFullScreen,
                    resolution:
                        _resolutionLabels[_resolution] ?? '${_resolution}p',
                    fps: _fps,
                    bitrate: _bitrate,
                    shareAudio: _shareAudio,
                    codec: _codec,
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
