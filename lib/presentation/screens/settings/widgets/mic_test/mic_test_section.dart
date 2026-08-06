import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../logic/services/mic_level_scale.dart';
import '../../../../common/app_button.dart';
import '../../../../theme/custom_colors.dart';
import 'widgets/input_sensitivity_slider.dart';
import 'widgets/mic_level_meter.dart';
import '../../../../theme/app_text.dart';

/// "Mic Test" settings block: opens the microphone with the current
/// audio-processing settings and shows a live input-level meter so the user
/// can confirm their mic works and see the effect of the processing toggles.
///
/// It creates its own standalone [LocalAudioTrack] (separate from any call) and
/// drives the meter from LiveKit's audio visualizer, tearing both down when the
/// test stops or the screen is disposed.
///
/// While it runs, a call in progress is muted and the mic handed over
/// explicitly — see [LiveKitCubit.setMicrophoneSuspended]. Two captures of one
/// device only appear to work: the test wins, the call quietly publishes
/// silence, and the mic never comes back when the test stops.
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

  LocalAudioTrack? _track;
  AudioVisualizer? _visualizer;
  EventsListener<AudioVisualizerEvent>? _listener;

  /// Held rather than read from `context`, because [dispose] has to give the
  /// microphone back and the element is already gone by then. Leaving the call
  /// muted because the user closed settings is the bug this whole change is
  /// about.
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
    final settings = context.read<AppCubit>().state;

    // Free the device before asking for it. On a Bluetooth headset there is
    // one capture stream, so the order matters.
    await _livekit?.setMicrophoneSuspended(true);

    LocalAudioTrack? track;
    AudioVisualizer? visualizer;
    try {
      // Match the real capture path so the meter reflects the processing
      // toggles; the input device follows the global Hardware selection.
      track = await LocalAudioTrack.create(
        AudioCaptureOptions(
          noiseSuppression: settings.noiseSuppression,
          echoCancellation: settings.echoCancellation,
          autoGainControl: settings.autoGainControl,
        ),
      );
      visualizer = createVisualizer(
        track,
        options: const AudioVisualizerOptions(
          barCount: 7,
          centeredBands: false,
        ),
      );
      final listener = visualizer.createListener()
        ..on<AudioVisualizerEvent>(_onVisualizerEvent);
      await visualizer.start();

      if (!mounted) {
        // Screen went away mid-start — don't leak the mic.
        await listener.dispose();
        await visualizer.stop();
        await visualizer.dispose();
        await track.stop();
        await track.dispose();
        await _livekit?.setMicrophoneSuspended(false);
        return;
      }

      setState(() {
        _track = track;
        _visualizer = visualizer;
        _listener = listener;
        _testing = true;
        _level = 0;
      });
    } catch (e) {
      await visualizer?.stop();
      await visualizer?.dispose();
      await track?.stop();
      await track?.dispose();
      // The test failed; the call must not keep paying for it.
      await _livekit?.setMicrophoneSuspended(false);
      if (mounted) {
        setState(
          () => _error =
              'Could not access the microphone. '
              'Close any app using it and try again.',
        );
      }
    }
  }

  void _onVisualizerEvent(AudioVisualizerEvent e) {
    final bands = e.event.whereType<num>().map((n) => n.toDouble());
    if (bands.isEmpty) return;
    final peak = bands.reduce((a, b) => a > b ? a : b).clamp(0.0, 1.0);
    if (!mounted) return;
    setState(() {
      // Fast attack, slow decay for a readable meter.
      _level = peak > _level ? peak.toDouble() : _level * 0.8 + peak * 0.2;
    });
  }

  Future<void> _stop() async {
    await _listener?.dispose();
    await _visualizer?.stop();
    await _visualizer?.dispose();
    await _track?.stop();
    await _track?.dispose();
    _listener = null;
    _visualizer = null;
    _track = null;
    // Only once this capture is fully gone — handing the device back before
    // releasing it is how you end up with neither side holding it.
    await _livekit?.setMicrophoneSuspended(false);
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
        final threshold = appState.voiceActivityThreshold;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Input Sensitivity',
              style: AppText.row.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: themeState.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'How loud your mic must be to transmit. Drag the threshold, then '
              'Test Mic and speak — input left of the marker is muted. Leave at '
              '0% for an open mic.',
              style: AppText.secondary.copyWith(
                color: themeState.textTertiary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 12),
            // Both drawn through MicLevelScale, so the bar and the marker
            // share one ruler — a voice reaching the marker is a voice that
            // opens the gate.
            MicLevelMeter(
              level: MicLevelScale.toPosition(_level),
              active: _testing,
              threshold: MicLevelScale.toPosition(threshold),
              themeState: themeState,
            ),
            const SizedBox(height: 10),
            InputSensitivitySlider(
              threshold: threshold,
              onChanged: context.read<AppCubit>().setVoiceActivityThreshold,
              themeState: themeState,
            ),
            if (appState.pushToTalkEnabled)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'Ignored while Push-to-Talk is on.',
                  style: AppText.label.copyWith(
                    color: themeState.textTertiary,
                    fontSize: 11,
                  ),
                ),
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                AppButton(
                  label: _testing ? 'Stop Test' : 'Test Mic',
                  onPressed: _busy ? null : _toggle,
                  variant: _testing
                      ? AppButtonVariant.secondary
                      : AppButtonVariant.primary,
                  isLoading: _busy,
                ),
                const SizedBox(width: 10),
                if (_testing)
                  Text(
                    'Listening…',
                    style: AppText.secondary.copyWith(
                      color: themeState.textTertiary,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: AppText.secondary.copyWith(
                  color: CustomColors.error,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
