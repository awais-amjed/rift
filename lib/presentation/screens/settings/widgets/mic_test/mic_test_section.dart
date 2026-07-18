import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/app_button.dart';
import '../../../../theme/custom_colors.dart';
import 'widgets/mic_level_meter.dart';

/// "Mic Test" settings block: opens the microphone with the current
/// audio-processing settings and shows a live input-level meter so the user
/// can confirm their mic works and see the effect of the processing toggles.
///
/// It creates its own standalone [LocalAudioTrack] (separate from any call) and
/// drives the meter from LiveKit's audio visualizer, tearing both down when the
/// test stops or the screen is disposed.
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
      if (mounted) {
        setState(() => _error = 'Could not access the microphone. '
            'Close any app using it and try again.');
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Mic Test',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: themeState.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Speak to check your input level. Uses your selected input device '
          'and the audio-processing settings above.',
          style: TextStyle(color: themeState.textTertiary, fontSize: 12),
        ),
        const SizedBox(height: 12),
        MicLevelMeter(
          level: _level,
          active: _testing,
          themeState: themeState,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            AppButton(
              label: _testing ? 'Stop Test' : 'Test Mic',
              onPressed: _busy ? null : _toggle,
              variant:
                  _testing ? AppButtonVariant.secondary : AppButtonVariant.primary,
              isLoading: _busy,
            ),
            const SizedBox(width: 10),
            if (_testing)
              Text(
                'Listening…',
                style: TextStyle(color: themeState.textTertiary, fontSize: 12),
              ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: const TextStyle(color: CustomColors.error, fontSize: 12),
          ),
        ],
      ],
    );
  }
}
