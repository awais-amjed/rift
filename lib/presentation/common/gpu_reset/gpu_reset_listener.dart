import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../logic/cubits/app/app_cubit.dart';
import '../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../logic/helper_methods.dart';
import '../../../logic/services/gpu_reset.dart';
import '../../../logic/services/tray_service/tray_service.dart';

/// Restarts Rift when the runner says the GPU its window draws with was lost,
/// back into the call it was in, as Restart to update does ([GpuReset]).
///
/// Nothing is asked: the window is white and cannot draw a question, and
/// what the restart takes, a few seconds of the call, is less than the
/// person would lose restarting by hand. The new copy says what happened.
/// Windows only, where the runner watches.
class GpuResetListener extends StatefulWidget {
  final Widget child;

  const GpuResetListener({super.key, required this.child});

  /// A loss this soon after a restart for one is not followed by another: a
  /// GPU that keeps going would restart Rift over and over.
  static const settleTime = Duration(minutes: 1);

  @override
  State<GpuResetListener> createState() => _GpuResetListenerState();
}

class _GpuResetListenerState extends State<GpuResetListener> {
  bool _restarting = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb || !Platform.isWindows) return;
    GpuReset.channel.setMethodCallHandler(_onCall);
    if (GpuReset.startedAfterReset) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => HelperMethods.showToast(
          title: 'Rift restarted',
          description: 'Your graphics driver restarted, so Rift did too.',
          autoCloseDuration: const Duration(seconds: 8),
        ),
      );
    }
  }

  @override
  void dispose() {
    if (!kIsWeb && Platform.isWindows) {
      GpuReset.channel.setMethodCallHandler(null);
    }
    super.dispose();
  }

  Future<void> _onCall(MethodCall call) async {
    if (call.method == 'lost') await _restart();
  }

  Future<void> _restart() async {
    if (_restarting || !mounted) return;
    if (GpuReset.startedAfterReset &&
        GpuReset.sinceStart < GpuResetListener.settleTime) {
      HelperMethods.printDebug(
        '[GPU] lost again right after restarting for it; not restarting again',
      );
      return;
    }
    _restarting = true;
    final app = context.read<AppCubit>();
    final call = context.read<LiveKitCubit>().state.toResume(DateTime.now());
    HelperMethods.printDebug(
      '[GPU] the window can no longer be drawn; restarting Rift'
      '${call == null ? '' : ' to rejoin the call'}',
    );
    if (!await GpuReset.relaunch()) {
      _restarting = false;
      return;
    }
    // Only once the new copy is on its way: one that could not start leaves
    // this one running, call and all.
    if (call != null) app.rememberCallToResume(call);
    await TrayService.instance.quit();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
