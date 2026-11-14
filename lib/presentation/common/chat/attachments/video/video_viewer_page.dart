import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/media/media_cubit.dart';
import '../../../../../logic/services/host_platform.dart';
import '../../../../../logic/services/window_fullscreen.dart';
import '../../../../theme/app_motion.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/media_colors.dart';
import '../../../context_menu/context_menu_watcher.dart';
import '../../../viewer_actions.dart';
import '../attachment_saving.dart';
import 'clip_playback.dart';
import 'widgets/video_controls.dart';
import 'widgets/video_icon_button.dart';
import 'widgets/video_keys.dart';
import 'widgets/video_middle.dart';

/// A chat video made bigger, two ways: in the window, as a picture opens
/// ([showImageViewer]: over a dark backdrop, a click beside it closes it),
/// or on the whole screen — the window full screen on a desktop, the
/// browser's on the web, the bars hidden on a phone. One goes to the other
/// with f; Esc comes back out of full screen to where it was opened.
///
/// It plays the card's own [ClipPlayback], so it goes on from where it was
/// and the card is where it was left when this goes. Its strip fades out
/// while it plays and the pointer is still, and comes back when it moves
/// (or, on a touch screen, with a tap). Its keys are [VideoKeys].
///
/// Over budget for a widget and one job: the two shapes share every
/// control, key and timer, and the picture moves between them.
class VideoViewerPage extends StatefulWidget {
  final ClipPlayback playback;

  /// Whether it opens on the whole screen, rather than in the window.
  final bool whole;

  const VideoViewerPage({
    super.key,
    required this.playback,
    required this.whole,
  });

  static Future<void> open(
    BuildContext context,
    ClipPlayback playback, {
    required bool whole,
  }) => Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      // In the window, the app stays behind the backdrop.
      opaque: false,
      transitionDuration: AppMotion.state,
      reverseTransitionDuration: AppMotion.state,
      pageBuilder: (_, _, _) =>
          VideoViewerPage(playback: playback, whole: whole),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );

  @override
  State<VideoViewerPage> createState() => _VideoViewerPageState();
}

class _VideoViewerPageState extends State<VideoViewerPage>
    with AttachmentSaving {
  static const Duration _idle = Duration(milliseconds: 2500);

  /// Round the video in the window: the image viewer's.
  static const double _inset = 24;

  /// The picture, moved rather than made again as it goes between the
  /// window and the whole screen: on the web it is a `<video>` element.
  final GlobalKey _picture = GlobalKey();

  late bool _whole = widget.whole;
  bool _shown = true;
  bool _leaving = false;

  /// The volume's panel is up over the strip: the strip stays while it is.
  bool _held = false;
  Timer? _hide;
  AppLifecycleListener? _away;

  ClipPlayback get _p => widget.playback;

  @override
  void initState() {
    super.initState();
    _p.addListener(_changed);
    _p.setFullscreen(true);
    if (_whole) {
      // After the frame: it tells the title bar at once, which is mid-build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(WindowFullscreen.set(true));
      });
    }
    HardwareKeyboard.instance.addHandler(_onKey);
    // The card's own, again: the card may go while this is open.
    if (HostPlatform.isMobile) _away = AppLifecycleListener(onHide: _p.pause);
    _poke();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _hide?.cancel();
    _away?.dispose();
    _p.removeListener(_changed);
    if (_p.cardGone) {
      _p.dispose();
    } else {
      _p.setFullscreen(false);
    }
    // Only if it is: a window told to leave a full screen it is not in
    // can lose its size.
    if (_whole) unawaited(WindowFullscreen.set(false));
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    // Stopped, it keeps its strip, as every player does.
    if (!_p.playing && !_shown) return _poke();
    setState(() {});
  }

  /// The strip shown, and hidden again after a still moment while it plays.
  void _poke() {
    _hide?.cancel();
    if (!_shown) setState(() => _shown = true);
    _hide = Timer(_idle, () {
      if (mounted && _p.playing && !_held) setState(() => _shown = false);
    });
  }

  void _toggle() {
    _poke();
    _p.toggle(output: context.read<AppCubit>().state.outputDeviceId);
  }

  void _setWhole(bool on) {
    if (_whole == on) return;
    setState(() => _whole = on);
    unawaited(WindowFullscreen.set(on));
    _poke();
  }

  /// Out of full screen to the window, where it was opened there; else
  /// closed.
  void _back() => _whole && !widget.whole ? _setWhole(false) : _leave();

  void _leave() {
    if (_leaving) return;
    _leaving = true;
    Navigator.of(context).maybePop();
  }

  /// Heard whatever has the focus, as the stream's page does: any click
  /// takes the focus away (`KeyboardDismisser`), and keys bound to the page
  /// would then go deaf.
  bool _onKey(KeyEvent event) {
    // A dialog or menu opened over it gets its own keys.
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return false;
    final done = VideoKeys.act(
      event,
      playback: _p,
      app: context.read<AppCubit>(),
      toggle: _toggle,
      fullscreen: () => _whole ? _back() : _setWhole(true),
      back: _back,
    );
    if (done) _poke();
    return done;
  }

  double get _ratio {
    final shape =
        _p.picture ??
        switch ((_p.attachment.width, _p.attachment.height)) {
          (final w?, final h?) when w > 0 && h > 0 => Size(
            w.toDouble(),
            h.toDouble(),
          ),
          _ => const Size(16, 9),
        };
    return shape.width / shape.height;
  }

  @override
  Widget build(BuildContext context) {
    // The card's, again, for when the card has gone.
    return BlocListener<AppCubit, AppState>(
      listenWhen: (prev, curr) =>
          prev.chatVideoVolume != curr.chatVideoVolume ||
          prev.chatVideoMuted != curr.chatVideoMuted,
      listener: (_, app) =>
          _p.setVolume(app.chatVideoMuted ? 0 : app.chatVideoVolume),
      child: Material(
        color: _whole ? MediaColors.videoGround : MediaColors.clear,
        child: MouseRegion(
          cursor: _shown ? MouseCursor.defer : SystemMouseCursors.none,
          onHover: (_) => _poke(),
          // The volume's panel is drawn over the page, so the pointer on it
          // is off the page as far as the hover above can tell.
          child: ContextMenuWatcher(
            onOpened: () {
              _held = true;
              _poke();
            },
            onClosed: () {
              _held = false;
              if (mounted) _poke();
            },
            child: _whole ? _wholeScreen() : _inWindow(),
          ),
        ),
      ),
    );
  }

  bool get _showsMiddle =>
      !_p.playing || _p.opening || _p.waiting || _p.problem != null;

  Widget _wholeScreen() => Stack(
    fit: StackFit.expand,
    children: [
      _surface(Center(child: _video())),
      if (_showsMiddle) _middle(),
      Positioned(left: 0, right: 0, top: 0, child: _fading(_top())),
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: _fading(
          _shade(up: true, child: SafeArea(top: false, child: _strip())),
        ),
      ),
    ],
  );

  /// As a picture opens: the video on a dark backdrop, which closes it.
  Widget _inWindow() => Stack(
    fit: StackFit.expand,
    children: [
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _leave,
        child: const ColoredBox(color: MediaColors.viewerBarrier),
      ),
      Padding(
        padding: const EdgeInsets.all(_inset),
        child: Center(
          child: AspectRatio(
            aspectRatio: _ratio,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(K.radiusCard),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _surface(_video()),
                  if (_showsMiddle) _middle(),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _fading(_shade(up: true, child: _strip())),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      Positioned(
        top: _inset + 8,
        right: _inset + 8,
        child: _fading(
          ViewerActions(
            onSave: () => saveFile(_p.loader, _p.attachment),
            onClose: _leave,
            saving: savingNow
                ? SaveProgressGlyph(
                    busy: true,
                    progress: saveProgress,
                    onMedia: true,
                  )
                : null,
          ),
        ),
      ),
    ],
  );

  /// What a press on the picture does: a click plays and pauses; a tap on
  /// a touch screen shows or hides the strip, as phone players do.
  Widget _surface(Widget child) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTapUp: (d) {
      if (d.kind != PointerDeviceKind.touch) return _toggle();
      if (!_shown) return _poke();
      _hide?.cancel();
      setState(() => _shown = false);
    },
    child: ColoredBox(color: MediaColors.videoGround, child: child),
  );

  /// The poster until the first picture lands, then the picture.
  Widget _video() {
    final posterPath = _p.attachment.poster?.storagePath;
    final poster = context.select<MediaCubit, Uint8List?>(
      (c) => posterPath == null
          ? null
          : c.state.entry(MediaKind.attachment, posterPath)?.bytes,
    );
    final clip = _p.clip;
    return AspectRatio(
      key: _picture,
      aspectRatio: _ratio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (poster != null)
            Image.memory(poster, fit: BoxFit.contain, gaplessPlayback: true),
          if (clip != null && _p.picture != null) clip.picture(),
        ],
      ),
    );
  }

  Widget _middle() => Center(
    child: GestureDetector(
      onTap: _toggle,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: VideoMiddle(
          loading: _p.opening || _p.waiting,
          ended: _p.ended,
          problem: _p.problem,
        ),
      ),
    ),
  );

  Widget _strip() => VideoControls(
    playback: _p,
    onToggle: _toggle,
    big: true,
    fullscreen: _whole,
    onFullscreen: () => _whole ? _back() : _setWhole(true),
  );

  Widget _fading(Widget child) => IgnorePointer(
    ignoring: !_shown,
    child: AnimatedOpacity(
      duration: AppMotion.state,
      opacity: _shown ? 1 : 0,
      child: child,
    ),
  );

  Widget _top() => _shade(
    up: false,
    child: SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 24),
        child: Row(
          spacing: 12,
          children: [
            Expanded(
              child: Text(
                _p.attachment.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.strong.copyWith(color: MediaColors.onMedia),
              ),
            ),
            VideoIconButton(
              icon: Icons.close_rounded,
              // Opened in the window, Esc goes back there instead.
              tooltip: widget.whole ? 'Close (Esc)' : 'Close',
              size: 26,
              onPressed: _leave,
            ),
          ],
        ),
      ),
    ),
  );

  /// A shade from the edge in, so white glyphs read on a white picture.
  Widget _shade({required bool up, required Widget child}) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: up ? Alignment.bottomCenter : Alignment.topCenter,
        end: up ? Alignment.topCenter : Alignment.bottomCenter,
        colors: const [MediaColors.panel, MediaColors.clear],
      ),
    ),
    child: child,
  );
}
