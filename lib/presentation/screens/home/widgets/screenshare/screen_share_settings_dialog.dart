import 'dart:io' show Platform;
import 'dart:math' show max;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sizer/sizer.dart';

import '../../../../../data/classes/screen_share_settings.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../src/rust/api/screenshare/audio_linux.dart';
import '../../../../../src/rust/api/screenshare/capture.dart';
import '../../../../../src/rust/api/screenshare/types.dart';
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

    _loadCaptureSources();

    // Linux uses explicit audio source selection only for full-screen capture.
    if (Platform.isLinux && _shareAudio && _captureFullScreen) {
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
        debugPrint(
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
      debugPrint('Failed to load capture sources: $e');
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
        debugPrint('Thumbnail load failed for source ${source.index}: $e');
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
      debugPrint('Failed to load audio sources: $e');
      if (mounted) {
        setState(() => _loadingAudioSources = false);
      }
    }
  }

  void _onAudioToggle() {
    setState(() => _shareAudio = !_shareAudio);

    // Load Linux audio sources only for full-screen sharing.
    if (Platform.isLinux &&
        _shareAudio &&
        _captureFullScreen &&
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
      selectedAudioSource: _captureFullScreen ? _selectedAudioSource : null,
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
                                if (!_captureFullScreen) {
                                  _selectedAudioSource = null;
                                }
                              });
                              _loadCaptureSources();

                              if (Platform.isLinux &&
                                  _shareAudio &&
                                  _captureFullScreen) {
                                _loadAudioSources();
                              }
                            },
                          ),
                          const SizedBox(height: 16),

                          _CaptureSourceSection(
                            captureFullScreen: _captureFullScreen,
                            isLoading: _loadingCaptureSources,
                            sources: _captureSources,
                            selectedIndex: _selectedVideoSourceIndex,
                            thumbnails: _thumbnails,
                            onChanged: (source) {
                              setState(() {
                                _selectedVideoSourceIndex = source.index;
                                _selectedVideoSourcePid = source.audioSourcePid;
                              });
                            },
                            onRefresh: _loadCaptureSources,
                          ),
                          const SizedBox(height: 16),

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

                          // Audio source selector (Linux only)
                          if (Platform.isLinux &&
                              _shareAudio &&
                              _captureFullScreen) ...[
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
                        onPressed: _selectedVideoSourceIndex == null
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

class _CaptureSourceSection extends StatelessWidget {
  final bool captureFullScreen;
  final bool isLoading;
  final List<CaptureSource>? sources;
  final int? selectedIndex;
  final Map<int, Uint8List> thumbnails;
  final ValueChanged<CaptureSource> onChanged;
  final Future<void> Function() onRefresh;

  const _CaptureSourceSection({
    required this.captureFullScreen,
    required this.isLoading,
    required this.sources,
    required this.selectedIndex,
    required this.thumbnails,
    required this.onChanged,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final label = captureFullScreen ? 'Screen' : 'Window';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Select $label',
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Refresh $label list',
              onPressed: isLoading ? null : onRefresh,
              icon: const Icon(Icons.refresh, size: 18),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (isLoading)
          const LinearProgressIndicator(minHeight: 2)
        else if (sources == null || sources!.isEmpty)
          Text('No $label sources found.')
        else if (Platform.isWindows)
          _SourceThumbnailGrid(
            sources: sources!,
            selectedIndex: selectedIndex,
            thumbnails: thumbnails,
            captureFullScreen: captureFullScreen,
            onChanged: onChanged,
          )
        else
          _SourceDropdown(
            sources: sources!,
            selectedIndex: selectedIndex,
            captureFullScreen: captureFullScreen,
            onChanged: onChanged,
          ),
      ],
    );
  }
}

// ── Dropdown fallback (Linux / non-Windows) ───────────────────────────────────

class _SourceDropdown extends StatelessWidget {
  final List<CaptureSource> sources;
  final int? selectedIndex;
  final bool captureFullScreen;
  final ValueChanged<CaptureSource> onChanged;

  const _SourceDropdown({
    required this.sources,
    required this.selectedIndex,
    required this.captureFullScreen,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final label = captureFullScreen ? 'Screen' : 'Window';
    final selectedSource =
        sources.where((s) => s.index == selectedIndex).firstOrNull;

    return DropdownButtonFormField<int>(
      key: ValueKey(
          '${captureFullScreen}_${selectedSource?.index}_${sources.length}'),
      initialValue: selectedSource?.index,
      isExpanded: true,
      decoration: InputDecoration(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      items: sources
          .map((s) => DropdownMenuItem<int>(
                value: s.index,
                child: Text(_displayLabel(s, label),
                    overflow: TextOverflow.ellipsis),
              ))
          .toList(),
      selectedItemBuilder: (context) => sources
          .map((s) => Align(
                alignment: Alignment.centerLeft,
                child: Text(_displayLabel(s, label),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ))
          .toList(),
      onChanged: (value) {
        if (value == null) return;
        final source = sources.where((s) => s.index == value).firstOrNull;
        if (source != null) onChanged(source);
      },
    );
  }

  String _displayLabel(CaptureSource source, String label) {
    final trimmed = source.title.trim();
    if (trimmed.isNotEmpty) return trimmed;
    return '$label #${source.index + 1} (index ${source.index})';
  }
}

// ── Thumbnail grid (Windows only) ────────────────────────────────────────────

class _SourceThumbnailGrid extends StatelessWidget {
  final List<CaptureSource> sources;
  final int? selectedIndex;
  final Map<int, Uint8List> thumbnails;
  final bool captureFullScreen;
  final ValueChanged<CaptureSource> onChanged;

  const _SourceThumbnailGrid({
    required this.sources,
    required this.selectedIndex,
    required this.thumbnails,
    required this.captureFullScreen,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Screens: 2 columns (there are usually just 1–3).
    // Windows: 3 columns (can be many).
    final crossAxisCount = captureFullScreen ? 2 : 3;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        // 16:9 card with a label strip below
        childAspectRatio: 16 / 11,
      ),
      itemCount: sources.length,
      itemBuilder: (context, i) {
        final source = sources[i];
        final isSelected = source.index == selectedIndex;
        final thumb = thumbnails[source.index];
        final label = _displayLabel(source);

        return _SourceCard(
          source: source,
          isSelected: isSelected,
          thumbnail: thumb,
          label: label,
          onTap: () => onChanged(source),
        );
      },
    );
  }

  String _displayLabel(CaptureSource source) {
    final typeLabel = captureFullScreen ? 'Screen' : 'Window';
    final trimmed = source.title.trim();
    if (trimmed.isNotEmpty) return trimmed;
    return '$typeLabel #${source.index + 1}';
  }
}

class _SourceCard extends StatelessWidget {
  final CaptureSource source;
  final bool isSelected;
  final Uint8List? thumbnail;
  final String label;
  final VoidCallback onTap;

  const _SourceCard({
    required this.source,
    required this.isSelected,
    required this.thumbnail,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final borderColor =
        isSelected ? colorScheme.primary : colorScheme.outlineVariant;
    final borderWidth = isSelected ? 2.5 : 1.0;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor, width: borderWidth),
          color: isSelected
              ? colorScheme.primary.withValues(alpha: 0.08)
              : colorScheme.surfaceContainerHighest,
        ),
        child: Column(
          children: [
            // Preview area (takes most of the card)
            Expanded(
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(7)),
                child: thumbnail != null
                    ? Image.memory(
                        thumbnail!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        gaplessPlayback: true,
                      )
                    : Center(
                        child: Icon(
                          Icons.desktop_windows_outlined,
                          size: 28,
                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                        ),
                      ),
              ),
            ),
            // Label strip
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight:
                      isSelected ? FontWeight.w700 : FontWeight.normal,
                  color: isSelected
                      ? colorScheme.primary
                      : colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
