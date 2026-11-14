import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/media/media_cubit.dart';
import '../../../../../logic/services/host_platform.dart';
import '../../../../../logic/services/window_fullscreen.dart';
import '../../../../theme/app_motion.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/media_colors.dart';
import '../../../context_menu/context_menu_watcher.dart';
import 'clip_playback.dart';
import 'widgets/video_controls.dart';
import 'widgets/video_icon_button.dart';
import 'widgets/video_middle.dart';

/// A chat video on the whole screen: the window full screen on a desktop, the
/// browser's on the web, the bars hidden on a phone.
///
/// It plays the card's own [ClipPlayback], so it goes on from where it was
/// and the card is where it was left when this goes. Its strip and title
/// fade out while it plays and the pointer is still, and come back when it
/// moves (or, on a touch screen, with a tap).
///
/// Its keys: space or k plays and pauses, the arrows go 5 s either way and
/// j and l 10 s, up and down change the volume, m mutes, 0 to 9 jump to that
/// tenth, and f or Esc leave.
class VideoFullscreenPage extends StatefulWidget {
  final ClipPlayback playback;

  const VideoFullscreenPage({super.key, required this.playback});

  static Future<void> open(BuildContext context, ClipPlayback playback) =>
      Navigator.of(context, rootNavigator: true).push(
        PageRouteBuilder<void>(
          transitionDuration: AppMotion.state,
          reverseTransitionDuration: AppMotion.state,
          pageBuilder: (_, _, _) => VideoFullscreenPage(playback: playback),
          transitionsBuilder: (_, animation, _, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      );

  @override
  State<VideoFullscreenPage> createState() => _VideoFullscreenPageState();
}

class _VideoFullscreenPageState extends State<VideoFullscreenPage> {
  static const Duration _idle = Duration(milliseconds: 2500);

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
    // After the frame: it tells the title bar at once, which is mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(WindowFullscreen.set(true));
    });
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
    unawaited(WindowFullscreen.set(false));
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    // Stopped, it keeps its strip, as every player does.
    if (!_p.playing && !_shown) return _poke();
    setState(() {});
  }

  /// The strip and title shown, and hidden again after a still moment
  /// while it plays.
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

  void _leave() {
    if (_leaving) return;
    _leaving = true;
    Navigator.of(context).maybePop();
  }

  /// Heard whatever has the focus, as the stream's page does: any click
  /// takes the focus away (`KeyboardDismisser`), and keys bound to the page
  /// would then go deaf.
  bool _onKey(KeyEvent event) {
    if (event is KeyUpEvent) return false;
    // A dialog or menu opened over it gets its own keys.
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return false;
    final key = event.logicalKey;
    final repeat = event is KeyRepeatEvent;
    final app = context.read<AppCubit>();
    void volumeBy(double by) =>
        app.setChatVideoVolume(app.state.chatVideoVolume + by);

    if (key == LogicalKeyboardKey.arrowLeft) {
      _p.skip(const Duration(seconds: -5));
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _p.skip(const Duration(seconds: 5));
    } else if (key == LogicalKeyboardKey.arrowUp) {
      volumeBy(0.1);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      volumeBy(-0.1);
    } else if (repeat) {
      return false;
    } else if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.keyF) {
      _leave();
    } else if (key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.keyK) {
      _toggle();
    } else if (key == LogicalKeyboardKey.keyJ) {
      _p.skip(const Duration(seconds: -10));
    } else if (key == LogicalKeyboardKey.keyL) {
      _p.skip(const Duration(seconds: 10));
    } else if (key == LogicalKeyboardKey.keyM) {
      app.setChatVideoMuted(!app.state.chatVideoMuted);
    } else if (_tenth(key) case final tenth?) {
      _p.seek(_p.length * (tenth / 10));
    } else {
      return false;
    }
    _poke();
    return true;
  }

  static int? _tenth(LogicalKeyboardKey key) {
    final label = key.keyLabel;
    if (label.length != 1) return null;
    final digit = label.codeUnitAt(0) - 0x30;
    return digit >= 0 && digit <= 9 ? digit : null;
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
    final posterPath = _p.attachment.poster?.storagePath;
    final poster = context.select<MediaCubit, Uint8List?>(
      (c) => posterPath == null
          ? null
          : c.state.entry(MediaKind.attachment, posterPath)?.bytes,
    );
    final clip = _p.clip;
    final showsMiddle =
        !_p.playing || _p.opening || _p.waiting || _p.problem != null;
    // The card's, again, for when the card has gone.
    return BlocListener<AppCubit, AppState>(
      listenWhen: (prev, curr) =>
          prev.chatVideoVolume != curr.chatVideoVolume ||
          prev.chatVideoMuted != curr.chatVideoMuted,
      listener: (_, app) =>
          _p.setVolume(app.chatVideoMuted ? 0 : app.chatVideoVolume),
      child: Material(
        color: MediaColors.videoGround,
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
            child: Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  // A click plays and pauses; a tap on a touch screen shows or
                  // hides the strip, as phone players do.
                  onTapUp: (d) {
                    if (d.kind == PointerDeviceKind.touch) {
                      if (_shown) {
                        _hide?.cancel();
                        setState(() => _shown = false);
                      } else {
                        _poke();
                      }
                    } else {
                      _toggle();
                    }
                  },
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: _ratio,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (poster != null)
                            Image.memory(
                              poster,
                              fit: BoxFit.contain,
                              gaplessPlayback: true,
                            ),
                          if (clip != null && _p.picture != null)
                            clip.picture(),
                        ],
                      ),
                    ),
                  ),
                ),
                if (showsMiddle)
                  Center(
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
                  ),
                Positioned(left: 0, right: 0, top: 0, child: _fading(_top())),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _fading(
                    _shade(
                      up: true,
                      child: SafeArea(
                        top: false,
                        child: VideoControls(
                          playback: _p,
                          onToggle: _toggle,
                          fullscreen: true,
                          onFullscreen: _leave,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

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
              tooltip: 'Close (Esc)',
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
