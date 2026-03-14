import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubits/app/app_cubit.dart';
import '../cubits/livekit/livekit_cubit.dart';

/// Global keyboard listener that maps the configured keybind to PTT pressed state.
class PushToTalkListener extends StatefulWidget {
  final Widget child;

  const PushToTalkListener({super.key, required this.child});

  @override
  State<PushToTalkListener> createState() => _PushToTalkListenerState();
}

class _PushToTalkListenerState extends State<PushToTalkListener>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      context.read<LiveKitCubit>().setPushToTalkPressed(false);
    }
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (kIsWeb || !Platform.isWindows) return false;

    final appState = context.read<AppCubit>().state;
    final keyId = appState.pushToTalkKeyId;
    if (!appState.pushToTalkEnabled || keyId == null) {
      return false;
    }

    if (event.logicalKey.keyId != keyId) {
      return false;
    }

    if (event is KeyUpEvent) {
      context.read<LiveKitCubit>().setPushToTalkPressed(false);
      return false;
    }

    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      context.read<LiveKitCubit>().setPushToTalkPressed(true);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

