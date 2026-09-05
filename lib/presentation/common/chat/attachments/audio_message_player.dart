import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../../../../data/classes/attachment.dart';
import '../../../../data/constants.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import 'attachment_loader.dart';
import '../../../theme/app_shadows.dart';
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
      constraints: const BoxConstraints(maxWidth: 300),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: theme.bgTertiary,
        borderRadius: BorderRadius.circular(K.radiusAttachment),
        border: Border.all(color: theme.borderElevated),
      ),
      child: Row(
        spacing: 10,
        children: [
          _playButton(theme),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(K.radiusPill),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor: theme.bgActive,
                    color: theme.primary,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _duration == Duration.zero
                      ? widget.attachment.name
                      : '${_fmt(_position)} / ${_fmt(_duration)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  // Ticks while playing, so it must not change width.
                  style: AppText.figure.copyWith(color: theme.textQuaternary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The design's transport control: a lit gradient disc, not a bare glyph —
  /// it is the one thing on the card you are meant to press.
  Widget _playButton(ThemeState theme) {
    return GestureDetector(
      onTap: _loading ? null : _toggle,
      child: MouseRegion(
        cursor: _loading ? SystemMouseCursors.basic : SystemMouseCursors.click,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            gradient: theme.actionGradient,
            shape: BoxShape.circle,
            boxShadow: AppShadows.accentGlow(
              theme.primary,
              blurRadius: 10,
              dy: 2,
            ),
          ),
          child: _loading
              ? const Padding(
                  padding: EdgeInsets.all(8),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Icon(
                  _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 17,
                ),
        ),
      ),
    );
  }
}
