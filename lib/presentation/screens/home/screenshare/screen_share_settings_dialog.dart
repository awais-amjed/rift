import 'dart:async';
import 'dart:math' show min;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/classes/screen_share_settings.dart';
import '../../../../data/classes/server_limits.dart';
import '../../../../data/constants.dart';
import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../../logic/services/host_platform.dart';
import '../../../../logic/services/screen_share_sources.dart';
import '../../../../src/rust/api/screenshare/types.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/theme_context.dart';
import 'widgets/share_advanced_page.dart';
import 'widgets/share_choose_page.dart';
import 'widgets/share_start_page.dart';

enum _Page { start, choose, advanced }

/// Over the widget budget and one job: a share's settings, held as a draft, the
/// source lists they need, and which page of them is showing.
///
/// Dialog for picking what to share and how, before a share starts: a desktop
/// and a browser's (a phone has `PhoneShareDialog`).
///
/// It opens on what to share ([ShareStartPage]), and pressing one is the action:
/// where the app lists the windows itself it moves on to the list
/// ([ShareChoosePage]), which is given the room a window needs to be recognised;
/// where the desktop or browser asks instead, the dialog closes for that. A PC
/// with one screen has nothing to ask, so Entire screen starts at once.
///
/// Holds a draft [ScreenShareSettings] that only reaches [AppCubit] when the
/// user confirms. The pages themselves only show it and report edits.
class ScreenShareSettingsDialog extends StatefulWidget {
  /// What the server this call is on allows a share to use, or
  /// [ServerLimits.unlimited]. Passed in rather than read
  /// from a cubit here: the caller is already holding the selected server,
  /// and a dialog is the wrong place to go looking for one.
  final int maxShareMbps;

  /// Whether the app lists the sources here. Null is what this platform does
  /// ([HostPlatform.picksShareSourceInApp]); a test says which it is testing.
  final bool? picksSourceInApp;

  /// How the sources are listed, which a test replaces.
  final Future<List<CaptureSource>> Function({required bool captureFullScreen})
  listSources;

  const ScreenShareSettingsDialog({
    super.key,
    this.maxShareMbps = ServerLimits.unlimited,
    this.picksSourceInApp,
    this.listSources = ScreenShareSources.listCapture,
  });

  @override
  State<ScreenShareSettingsDialog> createState() =>
      _ScreenShareSettingsDialogState();
}

class _ScreenShareSettingsDialogState extends State<ScreenShareSettingsDialog> {
  /// Between a page and the window's edge.
  static const _inset = 30.0;
  static const _pageWidth = 640.0;
  static const _chooseWidth = 1040.0;

  /// A very tall window would only leave blank below the tiles.
  static const _chooseMaxHeight = 820.0;

  late ScreenShareSettings _draft;
  _Page _page = _Page.start;

  /// A card's press is being answered, by listing the screens.
  bool _opening = false;

  List<CaptureSource>? _captureSources;
  bool _loadingCaptureSources = false;

  /// Which listing is the latest. Going back and pressing the other card leaves
  /// an earlier one running, whose answer is about the wrong kind of source.
  int _listing = 0;

  /// source index → JPEG bytes; only populated on Windows.
  final Map<int, Uint8List> _thumbnails = {};

  List<AudioSource>? _audioSources;
  bool _loadingAudioSources = false;

  bool get _picksSourceInApp =>
      widget.picksSourceInApp ?? HostPlatform.picksShareSourceInApp;

  /// Linux shares the sound of the app picked in Advanced, or of every app but
  /// Rift. Listed before Advanced is opened too, since a pick left from the
  /// last share may be of an app that has stopped.
  bool get _needsAudioSources =>
      HostPlatform.picksShareAudioSource && _draft.shareAudio;

  /// Whether the picked app is dropped for a whole screen — only where a
  /// whole screen takes every app's sound but Rift's instead.
  bool _dropsAudioSource(bool captureFullScreen) =>
      captureFullScreen && !HostPlatform.picksShareAudioSource;

  @override
  void initState() {
    super.initState();
    _draft = context.read<AppCubit>().state.screenShareSettings;
    if (_needsAudioSources) _loadAudioSources();
  }

  /// Lists the sources of the kind in the draft, and picks one. False if a
  /// later listing has overtaken this one.
  Future<bool> _listCaptureSources() async {
    final listing = ++_listing;
    setState(() => _loadingCaptureSources = true);
    final sources = await widget.listSources(
      captureFullScreen: _draft.captureFullScreen,
    );
    if (!mounted || listing != _listing) return false;

    final selected = ScreenShareSources.pickCaptureSource(sources, _draft);
    setState(() {
      _captureSources = sources;
      _loadingCaptureSources = false;
      _draft = selected == null
          ? _draft.copyWith(clearVideoSource: true)
          : _draft.withVideoSource(selected);
    });
    return true;
  }

  Future<void> _refreshCaptureSources() async {
    if (_loadingCaptureSources) return;
    if (await _listCaptureSources()) _startThumbnails();
  }

  /// Thumbnails trickle in behind the list; the list does not wait for them.
  void _startThumbnails() {
    final sources = _captureSources;
    if (HostPlatform.hasShareThumbnails && sources != null) {
      unawaited(_loadThumbnails(sources));
    }
  }

  /// Fetches JPEG thumbnails one source at a time (Windows only), updating
  /// state as each arrives so the grid populates progressively.
  Future<void> _loadThumbnails(List<CaptureSource> sources) async {
    final listing = _listing;
    final captureFullScreen = _draft.captureFullScreen;
    // Drop stale thumbnails from a previous load.
    setState(() => _thumbnails.clear());

    for (final source in sources) {
      final bytes = await ScreenShareSources.thumbnail(
        captureFullScreen: captureFullScreen,
        sourceIndex: source.index,
      );
      if (!mounted || listing != _listing) return;
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
      final selected = ScreenShareSources.keepAudioSource(
        sources,
        _draft.selectedAudioSource,
      );
      _draft = selected == null
          ? _draft.copyWith(clearAudioSource: true)
          : _draft.copyWith(selectedAudioSource: selected);
    });
  }

  /// A card was pressed. The last source picked stays picked if this is the
  /// same kind as last time.
  Future<void> _onKindPicked(bool captureFullScreen) async {
    final changed = captureFullScreen != _draft.captureFullScreen;
    setState(() {
      _draft = _draft.copyWith(
        captureFullScreen: captureFullScreen,
        clearVideoSource: changed,
        clearAudioSource: changed && _dropsAudioSource(captureFullScreen),
      );
      _captureSources = null;
      _thumbnails.clear();
    });
    if (!_picksSourceInApp) return _confirm();

    // The list of screens decides whether there is a page at all, so that one
    // is waited for; a window always has one, which shows it loading.
    if (captureFullScreen) {
      setState(() => _opening = true);
    } else {
      setState(() => _page = _Page.choose);
    }
    final listed = await _listCaptureSources();
    if (!mounted) return;
    setState(() => _opening = false);
    if (!listed) return;
    if (captureFullScreen && _captureSources?.length == 1) return _confirm();
    setState(() => _page = _Page.choose);
    _startThumbnails();
  }

  void _onAudioToggle() {
    setState(() => _draft = _draft.copyWith(shareAudio: !_draft.shareAudio));
    if (_needsAudioSources && _audioSources == null) _loadAudioSources();
  }

  void _goBack() {
    // A listing or thumbnails still on their way are of no use to the first page.
    _listing++;
    setState(() {
      _page = _Page.start;
      _loadingCaptureSources = false;
    });
  }

  void _onChanged(ScreenShareSettings settings) =>
      setState(() => _draft = settings);

  void _close() => Navigator.of(context).pop();

  void _confirm() {
    final settings = _dropsAudioSource(_draft.captureFullScreen)
        ? _draft.copyWith(clearAudioSource: true)
        : _draft;
    context.read<AppCubit>().setScreenShareSettings(settings);
    Navigator.of(context).pop(settings);
  }

  Widget _pageWidget() => switch (_page) {
    _Page.start => ShareStartPage(
      settings: _draft,
      maxShareMbps: widget.maxShareMbps,
      onChanged: _onChanged,
      onKindPicked: _opening ? null : _onKindPicked,
      onAudioToggle: _onAudioToggle,
      onAdvanced: () => setState(() => _page = _Page.advanced),
      onClose: _close,
    ),
    _Page.choose => ShareChoosePage(
      settings: _draft,
      isLoading: _loadingCaptureSources,
      sources: _captureSources,
      thumbnails: _thumbnails,
      onChanged: (source) => _onChanged(_draft.withVideoSource(source)),
      onRefresh: _refreshCaptureSources,
      onBack: _goBack,
      onClose: _close,
      onStart: _confirm,
    ),
    _Page.advanced => ShareAdvancedPage(
      settings: _draft,
      maxShareMbps: widget.maxShareMbps,
      onChanged: _onChanged,
      audioSources: _audioSources,
      loadingAudioSources: _loadingAudioSources,
      onRefreshAudioSources: _loadAudioSources,
      onDone: _goBack,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final window = MediaQuery.sizeOf(context);
    final choosing = _page == _Page.choose;
    final width = min(
      choosing ? _chooseWidth : _pageWidth,
      window.width - _inset * 2,
    );
    return PopScope(
      // Escape and a click outside go back a page first (`closeOnEscape`).
      canPop: _page == _Page.start,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goBack();
      },
      child: Dialog(
        insetPadding: const EdgeInsets.all(_inset),
        backgroundColor: theme.bgElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(K.radiusCard),
          side: BorderSide(color: theme.borderPrimary),
        ),
        child: AnimatedSize(
          duration: AppMotion.state,
          curve: AppMotion.settle,
          child: SizedBox(
            width: width,
            height: choosing
                ? min(_chooseMaxHeight, window.height - _inset * 2)
                : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: _pageWidget(),
            ),
          ),
        ),
      ),
    );
  }
}
