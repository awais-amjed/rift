import 'dart:async';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../../../../../data/constants.dart';
import '../../../../../logic/helper_methods.dart';
import '../../../../../src/rust/api/call_clip.dart';
import '../../../../../src/rust/api/cue.dart';
import '../../../../common/app_button.dart';

/// Plays the selection, and stops it, on the call's output device
/// ([outputId], as WebRTC lists it; the default when null). Built again for a
/// new selection, which stops what was playing: a preview is of one cut.
class ClipPreviewButton extends StatefulWidget {
  /// The selection, interleaved 16-bit: cut when Play is pressed, not on
  /// every step of a drag.
  final Int16List Function() selection;
  final int rate;
  final int channels;
  final String? outputId;

  const ClipPreviewButton({
    super.key,
    required this.selection,
    required this.rate,
    required this.channels,
    required this.outputId,
  });

  @override
  State<ClipPreviewButton> createState() => _ClipPreviewButtonState();
}

class _ClipPreviewButtonState extends State<ClipPreviewButton> {
  int? _playing;
  bool _starting = false;
  Timer? _ended;

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  void _stop() {
    _ended?.cancel();
    _ended = null;
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
      final output = widget.outputId;
      // WebRTC's own "default: …" entry is the system default.
      final onDefault =
          output == null || output.isEmpty || output.startsWith('default: ');
      final frames = pcm.length ~/ widget.channels;
      final started = await playSound(
        deviceId: onDefault ? null : output,
        bytes: wav,
        volume: 1,
        maxMs: frames * 1000 ~/ widget.rate + 250,
      );
      if (!mounted) {
        unawaited(stopCue(id: started.id));
        return;
      }
      setState(() {
        _playing = started.id;
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
