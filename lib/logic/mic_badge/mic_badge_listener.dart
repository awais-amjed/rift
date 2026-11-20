import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubits/app/app_cubit.dart';
import '../cubits/livekit/livekit_cubit.dart';
import '../helper_methods.dart';

/// Puts a mic on Rift's taskbar button and its tray icon while people in the
/// call can hear you, so it can be seen with a game in front of Rift. Windows
/// only: GNOME has no taskbar, and KDE's badges are numbers.
///
/// Live is [LiveKitState.micLive], the same rule the call sends the mic by, so
/// under push-to-talk it shows only while the key is held. The runner draws it
/// (`mic_badge.cpp`, and the tray's `TrayIcon::SetMicOn`) and keeps it through
/// the taskbar button being made again, as it is when Rift comes back from
/// the tray.
class MicBadgeListener extends StatefulWidget {
  final Widget child;

  const MicBadgeListener({super.key, required this.child});

  @override
  State<MicBadgeListener> createState() => _MicBadgeListenerState();
}

class _MicBadgeListenerState extends State<MicBadgeListener> {
  static const MethodChannel _channel = MethodChannel('rift/mic_badge');

  StreamSubscription<LiveKitState>? _call;
  StreamSubscription<AppState>? _settings;

  /// What the runner was last told.
  bool _live = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb || !Platform.isWindows) return;
    _call = context.read<LiveKitCubit>().stream.listen((_) => _tell());
    _settings = context.read<AppCubit>().stream.listen((_) => _tell());
  }

  @override
  void dispose() {
    _call?.cancel();
    _settings?.cancel();
    super.dispose();
  }

  void _tell() {
    final settings = context.read<AppCubit>().state;
    final live = context.read<LiveKitCubit>().state.micLive(
      pushToTalk: settings.pushToTalkEnabled,
      hasPushToTalkKey: settings.pushToTalkKeyId != null,
    );
    if (live == _live) return;
    _live = live;
    unawaited(_send(live));
  }

  Future<void> _send(bool live) async {
    try {
      await _channel.invokeMethod<void>('set', live);
    } on MissingPluginException {
      // A runner without the badge: nothing to show it on.
    } on PlatformException catch (e) {
      HelperMethods.printDebug('MicBadge: $e');
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
