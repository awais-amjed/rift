import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubits/livekit/livekit_cubit.dart';
import '../cubits/screenshare/screenshare_cubit.dart';
import '../services/pip_service.dart';

/// Tells the call whether anybody can see Rift, so a watched stream's
/// picture is turned off while nobody can ([LiveKitCubit.setAppSeen]), and
/// stops the animations below it meanwhile ([TickerMode]). The share hears it
/// too, to hold a notice found while a game covers Rift
/// ([ScreenshareCubit.setAppSeen]).
///
/// Minimised, or hidden to the tray, comes from the app lifecycle. On Windows
/// the lifecycle never says so, and the runner tells it instead
/// (`seen_watch.cpp`), along with what only it can see: another app's window
/// in front, covering all of Rift that is on screen, as a game in fullscreen
/// or a maximised browser does. Rift on another monitor, or only partly
/// covered, can still be seen and keeps its pictures. On Wayland the Linux
/// lifecycle never hears minimised either, and that runner tells it from the
/// compositor no longer asking Rift for frames, which it also stops for a
/// window wholly covered (`seen_watch.cc`).
class AppSeenListener extends StatefulWidget {
  final Widget child;

  const AppSeenListener({super.key, required this.child});

  /// Whether anybody can see Rift, for what waits until they can: the call
  /// clip view. Not [TickerMode], which a page pushed over the one asking
  /// turns off as well. True above this listener, where nothing is hidden.
  static bool seenFrom(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_AppSeen>()?.seen ?? true;

  @override
  State<AppSeenListener> createState() => _AppSeenListenerState();
}

class _AppSeenListenerState extends State<AppSeenListener>
    with WidgetsBindingObserver {
  static const EventChannel _kSeenChannel = EventChannel('rift/window_seen');

  StreamSubscription<dynamic>? _seenSub;
  bool _hidden = false;
  bool _windowSeen = true;

  /// What [_tell] last said, which also switches the animations below.
  bool _seen = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PipService.instance.isInPip.addListener(_tell);
    _hidden = _isHidden(WidgetsBinding.instance.lifecycleState);
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
      _seenSub = _kSeenChannel.receiveBroadcastStream().listen((seen) {
        _windowSeen = seen != false;
        _tell();
      });
    }
    _seen = _seenNow();
    context.read<LiveKitCubit>().setAppSeen(_seen);
    context.read<ScreenshareCubit>().setAppSeen(_seen);
  }

  @override
  void dispose() {
    _seenSub?.cancel();
    PipService.instance.isInPip.removeListener(_tell);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _hidden = _isHidden(state);
    _tell();
  }

  /// Inactive is still on screen: a window without the focus, or a phone's
  /// app switcher half open.
  static bool _isHidden(AppLifecycleState? state) => switch (state) {
    AppLifecycleState.hidden ||
    AppLifecycleState.paused ||
    AppLifecycleState.detached => true,
    AppLifecycleState.resumed || AppLifecycleState.inactive || null => false,
  };

  /// A phone's floating window shows the stream with the app put away.
  bool _seenNow() =>
      PipService.instance.isInPip.value || (!_hidden && _windowSeen);

  void _tell() {
    final seen = _seenNow();
    context.read<LiveKitCubit>().setAppSeen(seen);
    context.read<ScreenshareCubit>().setAppSeen(seen);
    if (seen != _seen && mounted) setState(() => _seen = seen);
  }

  /// Animations stop while nobody can see Rift. Each frame of one redraws
  /// the whole window, and on Windows that goes on minimised or covered by a
  /// game, as it does on Linux in the tray: there the old loading dots,
  /// which animated, cost 6.5% of a core for nobody, and 0.1% once stopped
  /// (Nov 15). A stopped animation picks up where its clock says when Rift
  /// is seen again, so whatever waits on one finishing waits until then.
  @override
  Widget build(BuildContext context) => _AppSeen(
    seen: _seen,
    child: TickerMode(enabled: _seen, child: widget.child),
  );
}

class _AppSeen extends InheritedWidget {
  final bool seen;

  const _AppSeen({required this.seen, required super.child});

  @override
  bool updateShouldNotify(_AppSeen oldWidget) => oldWidget.seen != seen;
}
