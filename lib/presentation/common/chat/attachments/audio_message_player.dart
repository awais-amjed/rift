import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../../../../data/classes/attachment.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import 'attachment_loader.dart';
import '../../../theme/app_text.dart';

/// Inline player for an audio attachment (voice note or attached audio file).
/// Bytes are fetched + decrypted lazily on first play via [loader]; playback is
/// driven by the `audioplayers` package from an in-memory [BytesSource].
class AudioMessagePlayer extends StatefulWidget {
  final Attachment attachment;
  final AttachmentLoader loader;
  final ThemeState themeState;

  const AudioMessagePlayer({
    super.key,
    required this.attachment,
    required this.loader,
    required this.themeState,
  });

  @override
  State<AudioMessagePlayer> createState() => _AudioMessagePlayerState();
}

class _AudioMessagePlayerState extends State<AudioMessagePlayer> {
  final AudioPlayer _player = AudioPlayer();
  Uint8List? _bytes;
  bool _loading = false;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    if (widget.attachment.durationMs != null) {
      _duration = Duration(milliseconds: widget.attachment.durationMs!);
    }
    _player.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() => _playing = state == PlayerState.playing);
    });
    _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _position = Duration.zero);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
      return;
    }
    if (_bytes == null) {
      setState(() => _loading = true);
      final data = await widget.loader(widget.attachment);
      if (!mounted) return;
      setState(() {
        _bytes = data;
        _loading = false;
      });
      if (data == null) return;
      await _player.play(BytesSource(data, mimeType: widget.attachment.mime));
    } else {
      await _player.resume();
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString();
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.themeState;
    final total = _duration.inMilliseconds == 0 ? 1 : _duration.inMilliseconds;
    final progress = (_position.inMilliseconds / total).clamp(0.0, 1.0);

    return Container(
      constraints: const BoxConstraints(maxWidth: 320),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.bgTertiary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.borderPrimary),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: _loading ? null : _toggle,
            visualDensity: VisualDensity.compact,
            icon: _loading
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.primary,
                    ),
                  )
                : Icon(
                    _playing
                        ? Icons.pause_circle_filled_rounded
                        : Icons.play_circle_fill_rounded,
                    color: theme.primary,
                    size: 30,
                  ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor: theme.borderPrimary,
                    color: theme.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _duration == Duration.zero
                      ? widget.attachment.name
                      : '${_fmt(_position)} / ${_fmt(_duration)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  // Ticks while playing, so it must not change width.
                  style: AppText.figure.copyWith(color: theme.textTertiary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
