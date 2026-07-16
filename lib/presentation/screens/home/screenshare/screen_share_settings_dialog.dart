import 'dart:io' show Platform;
import 'dart:math' show max;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sizer/sizer.dart';

import '../../../../../data/classes/screen_share_settings.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../logic/helper_methods.dart';
import '../../../../../src/rust/api/screenshare/audio_linux.dart';
import '../../../../../src/rust/api/screenshare/capture.dart';
import '../../../../../src/rust/api/screenshare/types.dart';
import '../../../common/app_button.dart';
import 'sections/audio_source_section.dart';
import 'widgets/audio_toggle.dart';
import 'sections/bitrate_section.dart';
import 'sections/capture_source_section.dart';
import 'sections/capture_type_section.dart';
import 'sections/codec_section.dart';
import 'sections/frame_rate_section.dart';
import 'sections/resolution_section.dart';
import 'widgets/settings_dialog_header.dart';
import 'widgets/settings_summary.dart';

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
  int? _selectedVideoSourceIndex;
  int? _selectedVideoSourcePid;
  late String _codec;

  List<CaptureSource>? _captureSources;
  bool _loadingCaptureSources = false;

  // source index → JPEG bytes; only populated on Windows
  final Map<int, Uint8List> _thumbnails = {};

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
    _selectedVideoSourceIndex = settings.selectedVideoSourceIndex;
    _selectedVideoSourcePid = settings.selectedVideoSourcePid;
    _codec = settings.codec;
    _selectedAudioSource = settings.selectedAudioSource;

    // On Linux the system portal picker handles source selection at capture time.
    if (!Platform.isLinux) {
      _loadCaptureSources();
    }

    // Linux uses explicit audio source selection only for window capture
    // (full-screen uses loopback / system audio automatically).
    if (Platform.isLinux && _shareAudio && !_captureFullScreen) {
      _loadAudioSources();
    }
  }

  Future<void> _loadCaptureSources() async {
    setState(() => _loadingCaptureSources = true);
    try {
      final sources = await listCaptureSources(
        captureFullScreen: _captureFullScreen,
      );
      final sourceTypeLabel = _captureFullScreen ? 'screen' : 'window';
      for (final source in sources) {
        HelperMethods.printDebug(
          '[CaptureSource][$sourceTypeLabel] index=${source.index} '
          'title="${source.title}" pid=${source.audioSourcePid}',
        );
      }
      if (!mounted) return;

      setState(() {
        _captureSources = sources;
        _loadingCaptureSources = false;

        if (sources.isEmpty) {
          _selectedVideoSourceIndex = null;
          _selectedVideoSourcePid = null;
          return;
        }

        final hasPersistedSource = sources.any(
          (source) => source.index == _selectedVideoSourceIndex,
        );

        final selectedSource = hasPersistedSource
            ? sources.firstWhere(
                (source) => source.index == _selectedVideoSourceIndex,
              )
            : sources.first;

        _selectedVideoSourceIndex = selectedSource.index;
        _selectedVideoSourcePid = selectedSource.audioSourcePid;
      });

      // Load per-source thumbnails on Windows after the source list is ready.
      if (Platform.isWindows) {
        _loadThumbnails(sources);
      }
    } catch (e) {
      HelperMethods.printDebug('Failed to load capture sources: $e');
      if (mounted) {
        setState(() => _loadingCaptureSources = false);
      }
    }
  }

  /// Fetches JPEG thumbnails for each source sequentially (Windows only).
  /// Updates state as each thumbnail arrives so the grid populates progressively.
  Future<void> _loadThumbnails(List<CaptureSource> sources) async {
    // Clear stale thumbnails from a previous source-type load.
    if (mounted) setState(() => _thumbnails.clear());

    for (final source in sources) {
      if (!mounted) return;
      try {
        final bytes = await getCaptureSourceThumbnail(
          captureFullScreen: _captureFullScreen,
          sourceIndex: source.index,
        );
        if (!mounted) return;
        if (bytes != null) {
          setState(() => _thumbnails[source.index] = bytes);
        }
      } catch (e) {
        HelperMethods.printDebug('Thumbnail load failed for source ${source.index}: $e');
      }
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
      HelperMethods.printDebug('Failed to load audio sources: $e');
      if (mounted) {
        setState(() => _loadingAudioSources = false);
      }
    }
  }

  void _onAudioToggle() {
    setState(() => _shareAudio = !_shareAudio);

    // Load Linux audio sources only for window sharing.
    if (Platform.isLinux &&
        _shareAudio &&
        !_captureFullScreen &&
        _audioSources == null) {
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
      selectedVideoSourceIndex: _selectedVideoSourceIndex,
      selectedVideoSourcePid: _selectedVideoSourcePid,
      codec: _codec,
      selectedAudioSource: !_captureFullScreen ? _selectedAudioSource : null,
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
        final bgColor = themeState.bgElevated;

        return Dialog(
          backgroundColor: bgColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: themeState.borderPrimary),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: max(480, 50.w),
              maxHeight: max(720, 80.h),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header (Always Visible)
                  SettingsDialogHeader(
                    onClose: () => Navigator.of(context).pop(),
                  ),
                  Divider(height: 24, color: themeState.borderPrimary),

                  // Scrollable Content
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Capture Type
                          CaptureTypeSection(
                            captureFullScreen: _captureFullScreen,
                            onChanged: (value) {
                              if (value == _captureFullScreen) return;
                              setState(() {
                                _captureFullScreen = value;
                                _captureSources = null;
                                _selectedVideoSourceIndex = null;
                                _selectedVideoSourcePid = null;
                                _thumbnails.clear();
                                // Clear audio source when switching to full screen
                                // (full-screen uses loopback, no source selection).
                                if (_captureFullScreen) {
                                  _selectedAudioSource = null;
                                }
                              });
                              if (!Platform.isLinux) {
                                _loadCaptureSources();
                              }

                              if (Platform.isLinux &&
                                  _shareAudio &&
                                  !_captureFullScreen) {
                                _loadAudioSources();
                              }
                            },
                          ),
                          const SizedBox(height: 16),

                          // Source selector — hidden on Linux (system portal picker handles it)
                          if (!Platform.isLinux) ...[
                            CaptureSourceSection(
                              captureFullScreen: _captureFullScreen,
                              isLoading: _loadingCaptureSources,
                              sources: _captureSources,
                              selectedIndex: _selectedVideoSourceIndex,
                              thumbnails: _thumbnails,
                              onChanged: (source) {
                                setState(() {
                                  _selectedVideoSourceIndex = source.index;
                                  _selectedVideoSourcePid =
                                      source.audioSourcePid;
                                });
                              },
                              onRefresh: _loadCaptureSources,
                            ),
                            const SizedBox(height: 16),
                          ],

                          // Resolution
                          ResolutionSection(
                            selectedResolution: _resolution,
                            onChanged: (value) =>
                                setState(() => _resolution = value),
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
                            onChanged: (value) =>
                                setState(() => _bitrate = value),
                          ),
                          const SizedBox(height: 16),

                          // Codec
                          CodecSection(
                            selectedCodec: _codec,
                            onChanged: (value) =>
                                setState(() => _codec = value),
                          ),
                          const SizedBox(height: 16),

                          // Share audio toggle
                          AudioToggle(
                            shareAudio: _shareAudio,
                            onToggle: _onAudioToggle,
                          ),

                          // Audio source selector (Linux, window capture only)
                          if (Platform.isLinux &&
                              _shareAudio &&
                              !_captureFullScreen) ...[
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
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Footer Actions (Always Visible)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      AppButton(
                        label: 'Cancel',
                        variant: AppButtonVariant.secondary,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 10),
                      AppButton(
                        label: 'Start Sharing',
                        onPressed:
                            (!Platform.isLinux &&
                                _selectedVideoSourceIndex == null)
                            ? null
                            : _confirm,
                      ),
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
