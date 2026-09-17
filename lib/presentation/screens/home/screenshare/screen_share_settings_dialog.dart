import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' show max;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sizer/sizer.dart';

import '../../../../../data/classes/screen_share_settings.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../logic/services/screen_share_sources.dart';
import '../../../../../src/rust/api/screenshare/types.dart';
import '../../../../data/constants.dart';
import '../../../common/app_button.dart';
import 'widgets/screen_share_settings_form.dart';
import 'widgets/settings_dialog_header.dart';

/// Dialog for configuring screen share settings (resolution, fps, bitrate,
/// audio) before a share starts.
///
/// Holds a draft [ScreenShareSettings] that only reaches [AppCubit] when the
/// user confirms, plus the source lists it loads on demand. The controls
/// themselves live in [ScreenShareSettingsForm].
class ScreenShareSettingsDialog extends StatefulWidget {
  const ScreenShareSettingsDialog({super.key});

  @override
  State<ScreenShareSettingsDialog> createState() =>
      _ScreenShareSettingsDialogState();
}

class _ScreenShareSettingsDialogState extends State<ScreenShareSettingsDialog> {
  late ScreenShareSettings _draft;

  List<CaptureSource>? _captureSources;
  bool _loadingCaptureSources = false;

  /// source index → JPEG bytes; only populated on Windows.
  final Map<int, Uint8List> _thumbnails = {};

  List<AudioSource>? _audioSources;
  bool _loadingAudioSources = false;

  bool get _needsAudioSources =>
      Platform.isLinux && _draft.shareAudio && !_draft.captureFullScreen;

  @override
  void initState() {
    super.initState();
    _draft = context.read<AppCubit>().state.screenShareSettings;

    // On Linux the system portal picker handles source selection at capture
    // time, so there is nothing to enumerate up front.
    if (!Platform.isLinux) _loadCaptureSources();
    if (_needsAudioSources) _loadAudioSources();
  }

  Future<void> _loadCaptureSources() async {
    setState(() => _loadingCaptureSources = true);
    final sources = await ScreenShareSources.listCapture(
      captureFullScreen: _draft.captureFullScreen,
    );
    if (!mounted) return;

    final selected = ScreenShareSources.pickCaptureSource(
      sources,
      _draft.selectedVideoSourceIndex,
    );
    setState(() {
      _captureSources = sources;
      _loadingCaptureSources = false;
      _draft = selected == null
          ? _draft.copyWith(clearVideoSource: true)
          : _draft.copyWith(
              selectedVideoSourceIndex: selected.index,
              selectedVideoSourcePid: selected.audioSourcePid,
            );
    });

    // Thumbnails trickle in behind the list; the list does not wait for them.
    if (Platform.isWindows) unawaited(_loadThumbnails(sources));
  }

  /// Fetches JPEG thumbnails one source at a time (Windows only), updating
  /// state as each arrives so the grid populates progressively.
  Future<void> _loadThumbnails(List<CaptureSource> sources) async {
    // Drop stale thumbnails from a previous source-type load.
    if (mounted) setState(() => _thumbnails.clear());

    for (final source in sources) {
      if (!mounted) return;
      final bytes = await ScreenShareSources.thumbnail(
        captureFullScreen: _draft.captureFullScreen,
        sourceIndex: source.index,
      );
      if (!mounted) return;
      if (bytes != null) setState(() => _thumbnails[source.index] = bytes);
    }
  }

  Future<void> _loadAudioSources() async {
    setState(() => _loadingAudioSources = true);
    final sources = await ScreenShareSources.listAudio();
    if (!mounted) return;
    setState(() {
      _audioSources = sources;
      _loadingAudioSources = false;
      final selected = ScreenShareSources.pickAudioSource(
        sources,
        _draft.selectedAudioSource,
      );
      _draft = selected == null
          ? _draft.copyWith(clearAudioSource: true)
          : _draft.copyWith(selectedAudioSource: selected);
    });
  }

  void _onCaptureTypeChanged(bool captureFullScreen) {
    if (captureFullScreen == _draft.captureFullScreen) return;
    setState(() {
      // Full-screen capture uses loopback audio, so any window-scoped audio
      // source no longer applies.
      _draft = _draft.copyWith(
        captureFullScreen: captureFullScreen,
        clearVideoSource: true,
        clearAudioSource: captureFullScreen,
      );
      _captureSources = null;
      _thumbnails.clear();
    });

    if (!Platform.isLinux) _loadCaptureSources();
    if (_needsAudioSources) _loadAudioSources();
  }

  void _onAudioToggle() {
    setState(() => _draft = _draft.copyWith(shareAudio: !_draft.shareAudio));
    if (_needsAudioSources && _audioSources == null) _loadAudioSources();
  }

  void _confirm() {
    // A window-scoped audio source is meaningless for full-screen capture.
    final settings = _draft.captureFullScreen
        ? _draft.copyWith(clearAudioSource: true)
        : _draft;
    context.read<AppCubit>().setScreenShareSettings(settings);
    Navigator.of(context).pop(settings);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Dialog(
          backgroundColor: themeState.bgElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(K.radiusCard),
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
                  SettingsDialogHeader(
                    onClose: () => Navigator.of(context).pop(),
                  ),
                  Divider(height: 24, color: themeState.borderPrimary),
                  Flexible(
                    child: ScreenShareSettingsForm(
                      settings: _draft,
                      onChanged: (settings) =>
                          setState(() => _draft = settings),
                      captureSources: _captureSources,
                      loadingCaptureSources: _loadingCaptureSources,
                      thumbnails: _thumbnails,
                      onRefreshCaptureSources: _loadCaptureSources,
                      audioSources: _audioSources,
                      loadingAudioSources: _loadingAudioSources,
                      onRefreshAudioSources: _loadAudioSources,
                      onCaptureTypeChanged: _onCaptureTypeChanged,
                      onAudioToggle: _onAudioToggle,
                    ),
                  ),
                  const SizedBox(height: 20),
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
                        label: 'Start sharing',
                        onPressed:
                            (!Platform.isLinux &&
                                _draft.selectedVideoSourceIndex == null)
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
