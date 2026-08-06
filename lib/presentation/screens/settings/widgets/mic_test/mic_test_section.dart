import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../logic/services/mic_test_capture.dart';
import 'widgets/input_sensitivity_panel.dart';
import 'widgets/mic_test_controls.dart';

/// "Mic Test" settings block: shows a live input-level meter so the user can
/// confirm their mic works, see the effect of the processing toggles, and set
/// the noise-gate threshold against something they can watch.
///
/// Where the level comes from depends on whether a call already owns the
/// microphone:
///
/// - **In a call, mic live** — it reads [LiveKitCubit.micLevels], the tap
///   already running for the noise gate. No second capture, so nothing to hand
///   back, and the meter shows the very signal being published.
/// - **Otherwise** — no call, or muted, so nothing holds the device — it opens
///   its own microphone through [MicTestCapture] and releases it when the test
///   stops or the screen is disposed.
///
/// It used to always open its own capture. On a Bluetooth headset there is a
/// single HFP stream, so that quietly took the device off the call, which then
/// published silence and never got it back. Taking turns instead of sharing
/// did not work either: releasing the device drops the headset's HFP profile,
/// and renegotiating it is slow enough that the new capture opens against a
/// microphone that is not there yet.
class MicTestSection extends StatefulWidget {
  final ThemeState themeState;

  const MicTestSection({super.key, required this.themeState});

  @override
  State<MicTestSection> createState() => _MicTestSectionState();
}

class _MicTestSectionState extends State<MicTestSection> {
  bool _testing = false;
  bool _busy = false;
  double _level = 0;
  String? _error;

  final MicTestCapture _capture = MicTestCapture();

  /// Set instead of using [_capture] when the call's tap is being borrowed.
  StreamSubscription<double>? _borrowedLevels;

  /// Held rather than read from `context`: [dispose] has to release the
  /// microphone, and the element is already gone by then.
  LiveKitCubit? _livekit;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _livekit = context.read<LiveKitCubit>();
  }

  Future<void> _toggle() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (_testing) {
        await _stop();
      } else {
        await _start();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    setState(() => _error = null);

    // The call already has the microphone open — read its tap rather than
    // fighting it for the device.
    final livekit = _livekit;
    if (livekit != null && livekit.isMicLevelAvailable) {
      _borrowedLevels = livekit.micLevels.listen(_onLevel);
      setState(() {
        _testing = true;
        _level = 0;
      });
      return;
    }

    // Match the real capture path so the meter reflects the processing
    // toggles; the input device follows the global Hardware selection.
    final settings = context.read<AppCubit>().state;
    try {
      await _capture.start(
        options: AudioCaptureOptions(
          noiseSuppression: settings.noiseSuppression,
          echoCancellation: settings.echoCancellation,
          autoGainControl: settings.autoGainControl,
        ),
        onLevel: _onLevel,
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not access the microphone. '
              'Close any app using it and try again.',
        );
      }
      return;
    }

    if (!mounted) {
      // Screen went away mid-start — don't leak the mic.
      await _capture.stop();
      return;
    }
    setState(() {
      _testing = true;
      _level = 0;
    });
  }

  void _onLevel(double level) {
    if (!mounted) return;
    setState(() {
      // Fast attack, slow decay for a readable meter.
      _level = level > _level ? level : _level * 0.8 + level * 0.2;
    });
  }

  Future<void> _stop() async {
    // Borrowed levels own nothing — dropping the subscription is the whole
    // teardown.
    await _borrowedLevels?.cancel();
    _borrowedLevels = null;
    await _capture.stop();

    if (mounted) {
      setState(() {
        _testing = false;
        _level = 0;
      });
    }
  }

  @override
  void dispose() {
    // Fire-and-forget: releases the mic even though dispose can't await.
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeState = widget.themeState;
    return BlocBuilder<AppCubit, AppState>(
      buildWhen: (a, b) =>
          a.voiceActivityThreshold != b.voiceActivityThreshold ||
          a.pushToTalkEnabled != b.pushToTalkEnabled,
      builder: (context, appState) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InputSensitivityPanel(
              level: _level,
              testing: _testing,
              threshold: appState.voiceActivityThreshold,
              onThresholdChanged: context
                  .read<AppCubit>()
                  .setVoiceActivityThreshold,
              pushToTalkEnabled: appState.pushToTalkEnabled,
              themeState: themeState,
            ),
            const SizedBox(height: 10),
            MicTestControls(
              testing: _testing,
              busy: _busy,
              error: _error,
              onToggle: _toggle,
              themeState: themeState,
            ),
          ],
        );
      },
    );
  }
}
