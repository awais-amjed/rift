import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/screen_share_settings.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../src/rust/api/screenshare/audio_linux.dart';
import '../../../../common/app_button.dart';
import '../../../../theme/custom_colors.dart';
import 'audio_source_section.dart';
import 'audio_toggle.dart';
import 'bitrate_section.dart';
import 'capture_type_section.dart';
import 'codec_section.dart';
import 'frame_rate_section.dart';
import 'resolution_section.dart';
import 'settings_dialog_header.dart';
import 'settings_summary.dart';

/// Dialog for configuring screen share settings (resolution, fps, bitrate, audio).
class ScreenShareSettingsDialog extends StatefulWidget {
  const ScreenShareSettingsDialog({super.key});

  @override
  State<ScreenShareSettingsDialog> createState() =>
      _ScreenShareSettingsDialogState();
}

class _ScreenShareSettingsDialogState extends State<ScreenShareSettingsDialog> {
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

  String _getResolutionLabel(int resolution) {
    const labels = {720: '720p', 1080: '1080p', 1440: '2K', 2160: '4K'};
    return labels[resolution] ?? '${resolution}p';
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
            constraints: const BoxConstraints(maxWidth: 480, maxHeight: 720),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    SettingsDialogHeader(
                      onClose: () => Navigator.of(context).pop(),
                    ),
                    Divider(height: 24, color: themeState.borderPrimary),

                    // Capture Type
                    CaptureTypeSection(
                      captureFullScreen: _captureFullScreen,
                      onChanged: (value) =>
                          setState(() => _captureFullScreen = value),
                    ),
                    const SizedBox(height: 16),

                    // Resolution
                    ResolutionSection(
                      selectedResolution: _resolution,
                      onChanged: (value) => setState(() => _resolution = value),
                    ),
                    const SizedBox(height: 16),

                    // FPS
                    FrameRateSection(
                      selectedFps: _fps,
                      onChanged: (value) => setState(() => _fps = value),
                    ),
                    const SizedBox(height: 16),

                    // Bitrate
                    BitrateSection(
                      selectedBitrate: _bitrate,
                      onChanged: (value) => setState(() => _bitrate = value),
                    ),
                    const SizedBox(height: 16),

                    // Codec
                    CodecSection(
                      selectedCodec: _codec,
                      onChanged: (value) => setState(() => _codec = value),
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
                      AudioSourceSection(
                        audioSources: _audioSources,
                        selectedAudioSource: _selectedAudioSource,
                        isLoading: _loadingAudioSources,
                        onChanged: (source) =>
                            setState(() => _selectedAudioSource = source),
                        onRefresh: _loadAudioSources,
                      ),
                    ],

                    const SizedBox(height: 16),
                    // Summary
                    SettingsSummary(
                      captureFullScreen: _captureFullScreen,
                      resolution: _getResolutionLabel(_resolution),
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
          ),
        );
      },
    );
  }
}
