import 'dart:async';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../../../../../data/constants.dart';
import '../../../../../logic/helper_methods.dart';
import '../../../../../logic/services/call_clip/clip_output.dart';
import '../../../../../src/rust/api/call_clip.dart';
import '../../../../../src/rust/api/cue.dart';
import '../../../../common/app_button.dart';

/// Plays the selection, and stops it, on the call's output device
/// ([outputId], as WebRTC lists it; the default when null or gone). Built again for a
/// new selection, which stops what was playing: a preview is of one cut.
///
/// While it plays it steps [played], the time since the sound started, for
/// the line over the waveform (`ClipPlayLine`), and sets it back to null when
/// it stops.
class ClipPreviewButton extends StatefulWidget {
  /// The selection, interleaved 16-bit: cut when Play is pressed, not on
  /// every step of a drag.
  final Int16List Function() selection;
  final int rate;
  final int channels;
  final String? outputId;
  final ValueNotifier<Duration?> played;

  const ClipPreviewButton({
    super.key,
    required this.selection,
    required this.rate,
    required this.channels,
    required this.outputId,
    required this.played,
  });

  @override
  State<ClipPreviewButton> createState() => _ClipPreviewButtonState();
}

class _ClipPreviewButtonState extends State<ClipPreviewButton> {
  /// How often the line moves: stepped, not animated, as anything that runs
  /// for a while is (AGENTS.md). Thirty rather than the usual fifteen, since
  /// this is watched while it moves, and it runs only while a preview plays.
  static const Duration _step = Duration(milliseconds: 33);

  int? _playing;
  bool _starting = false;
  Timer? _ended;
  Timer? _steps;

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  void _stop() {
    _ended?.cancel();
    _ended = null;
    _steps?.cancel();
    _steps = null;
    widget.played.value = null;
    final id = _playing;
    _playing = null;
    if (id != null) unawaited(stopCue(id: id));
  }

  Future<void> _toggle() async {
    if (_playing != null) {
      setState(_stop);
      return;
    }
    final pcm = widget.selection();
    if (_starting || pcm.isEmpty) return;
    setState(() => _starting = true);
    try {
      final wav = await callClipWav(
        pcm: pcm,
        rate: widget.rate,
        channels: widget.channels,
      );
      final frames = pcm.length ~/ widget.channels;
      final started = await ClipOutput.play(
        widget.outputId,
        (device) => playSound(
          deviceId: device,
          bytes: wav,
          volume: 1,
          maxMs: frames * 1000 ~/ widget.rate + 250,
        ),
      );
      if (!mounted) {
        unawaited(stopCue(id: started.id));
        return;
      }
      final clock = Stopwatch()..start();
      widget.played.value = Duration.zero;
      setState(() {
        _playing = started.id;
        _steps = Timer.periodic(
          _step,
          (_) => widget.played.value = clock.elapsed,
        );
        _ended = Timer(
          Duration(milliseconds: started.durationMs),
          () => mounted ? setState(_stop) : null,
        );
      });
    } catch (e) {
      HelperMethods.printDebug('[Clips] preview failed: $e');
      HelperMethods.showError(error: "Couldn't play the clip.");
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final playing = _playing != null;
    return AppButton(
      label: playing ? 'Stop' : 'Play',
      variant: AppButtonVariant.secondary,
      isLoading: _starting,
      icon: Icon(
        playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
        size: K.iconButton,
      ),
      onPressed: _toggle,
    );
  }
}
