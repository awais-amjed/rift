import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../../logic/services/audio_devices.dart';
import '../../../../../logic/services/host_platform.dart';
import '../../../../../logic/services/mic_test_capture.dart';
import '../../../../../logic/services/noise_filter.dart';
import '../../../../../src/rust/api/mic_test.dart';
import 'widgets/input_level_panel.dart';
import 'widgets/mic_test_controls.dart';

/// "Mic Test" settings block: shows a live input-level meter so the user can
/// confirm their mic works and see the effect of the processing toggles.
///
/// **On Windows, Linux and the web** it opens its own microphone through
/// [MicTestCapture] and plays it back on the chosen output, so you hear what
/// Rift hears. For as long as it runs you are muted and deafened in the app
/// ([LiveKitCubit.setMicTesting]): nobody in a call hears you testing, and the
/// call does not talk over your own voice. Pressing mute or deafen ends it.
///
/// The order matters on a Bluetooth headset, which drops its microphone when
/// the last holder lets go and is slow to bring it back for whoever opens
/// next: the test opens its capture before the call lets go, and the call
/// takes the microphone back before the test releases it.
///
/// **On Android and macOS** there is nothing to play it back with yet, so it
/// only draws the meter:
///
/// - **In a call with the mic on** — it reads [LiveKitCubit.micLevels], the tap
///   already running for the speaking indicator. No second capture, so nothing
///   to hand back, and the meter shows the very signal being published. Under
///   push-to-talk that means the meter sits at silence between presses, which
///   is the truth: nothing is being captured then either.
/// - **Otherwise** — no call, or muted, so nothing holds the device — it opens
///   its own microphone and releases it when the test stops or the screen is
///   disposed.
///
/// A second capture there used to take a Bluetooth headset's single HFP
/// stream off the call, which then published silence and never got it back.
class MicTestSection extends StatefulWidget {
  const MicTestSection({super.key});

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

  /// Whether this test plays the microphone back, and so mutes and deafens
  /// you while it runs.
  static bool get _hearsYourself => HostPlatform.micTestPlaysBack;

  Future<void> _start() async {
    setState(() => _error = null);

    // The call has the microphone, or is about to — read its tap rather than
    // fighting it for the device.
    final livekit = _livekit;
    if (!_hearsYourself && livekit != null && livekit.isCallHoldingMic) {
      _borrowedLevels = livekit.micLevels.listen(_onLevel);
      setState(() {
        _testing = true;
        _level = 0;
      });
      return;
    }

    if (!await _openCapture()) return;
    if (!mounted) {
      // Screen went away mid-start — don't leak the mic.
      await _capture.stop();
      return;
    }
    if (_hearsYourself) await livekit?.setMicTesting(true);
    if (!mounted) {
      await _stop();
      return;
    }
    setState(() {
      _testing = true;
      _level = 0;
    });
  }

  /// Opens the test's own capture on the chosen input — and, where it plays
  /// back, the chosen output — or says why not. False when it could not.
  Future<bool> _openCapture() async {
    // Match the real capture path so the meter reflects the processing
    // toggles and the chosen input. Without a device the plugin would move
    // the capture to the first listed input.
    final settings = context.read<AppCubit>().state;
    final deviceId = await AudioDevices.preferredInputId(
      settings.inputDeviceId,
    );
    if (!mounted) return false;
    try {
      await _capture.start(
        options: AudioCaptureOptions(
          deviceId: deviceId,
          noiseSuppression: NoiseFilter.usesBuiltIn(settings.noiseSuppression),
          echoCancellation: settings.echoCancellation,
          autoGainControl: settings.autoGainControl,
        ),
        // At the call's own volume, short of boosting it: past full scale is
        // clipping, and this is your own voice in your ears.
        playback: _hearsYourself
            ? MicTestPlayback(
                deviceId: settings.outputDeviceId,
                volume: settings.outputVolume.clamp(0, 1).toDouble(),
              )
            : null,
        onLevel: _onLevel,
      );
      return true;
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not access the microphone. '
              'Close any app using it and try again.',
        );
      }
      return false;
    }
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
    // The call takes the microphone back before the test lets go of it.
    await _livekit?.setMicTesting(false);
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

  /// A test reading its own capture opened the devices that were chosen
  /// when it started. Picking another one would leave the meter, or the
  /// playback, on the old device, so the capture starts over on the new one —
  /// without ending the test, which would unmute you in the call for a
  /// moment. A borrowed call tap follows the call by itself.
  Future<void> _onDeviceChanged() async {
    if (!_testing || _busy || !_capture.isRunning) return;
    setState(() => _busy = true);
    try {
      await _capture.stop();
      if (!await _openCapture()) await _stop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Pressing mute or deafen ends the test from outside — see
  /// [LiveKitCubit.toggleDeafen] — and the capture goes with it.
  void _onMicTestingChanged(bool testing) {
    if (!testing && _testing && !_busy) _toggle();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<AppCubit, AppState>(
          listenWhen: (a, b) =>
              a.inputDeviceId != b.inputDeviceId ||
              a.outputDeviceId != b.outputDeviceId,
          listener: (_, _) => _onDeviceChanged(),
        ),
        BlocListener<LiveKitCubit, LiveKitState>(
          listenWhen: (a, b) => a.isMicTesting != b.isMicTesting,
          listener: (_, state) => _onMicTestingChanged(state.isMicTesting),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InputLevelPanel(level: _level, testing: _testing),
          const SizedBox(height: 10),
          MicTestControls(
            testing: _testing,
            busy: _busy,
            error: _error,
            hearsYourself: _hearsYourself,
            onToggle: _toggle,
          ),
        ],
      ),
    );
  }
}
