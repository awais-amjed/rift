import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubits/livekit/livekit_cubit.dart';
import '../services/pip_service.dart';

/// Tells the call whether anybody can see Rift, so a watched stream's
/// picture is turned off while nobody can ([LiveKitCubit.setAppSeen]).
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

  @override
  State<AppSeenListener> createState() => _AppSeenListenerState();
}

class _AppSeenListenerState extends State<AppSeenListener>
    with WidgetsBindingObserver {
  static const EventChannel _kSeenChannel = EventChannel('rift/window_seen');

  StreamSubscription<dynamic>? _seenSub;
  bool _hidden = false;
  bool _windowSeen = true;

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
    _tell();
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
  void _tell() => context.read<LiveKitCubit>().setAppSeen(
    PipService.instance.isInPip.value || (!_hidden && _windowSeen),
  );

  @override
  Widget build(BuildContext context) => widget.child;
}
