import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/classes/attachment.dart';
import '../../../../data/constants.dart';
import '../../../../logic/cubits/media/media_cubit.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../logic/services/chat_audio_source.dart';
import '../../../../logic/services/media_sniff.dart';
import '../../../theme/app_shadows.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';
import '../../loading_dots.dart';
import 'attachment_loader.dart';
import 'attachment_saving.dart';
import 'video/attachment_video_card.dart';

/// Inline player for an audio attachment (voice note or attached audio file).
/// Bytes are fetched + decrypted lazily on first play via [loader]; playback is
/// driven by the `audioplayers` package, from memory where it can
/// ([ChatAudioSource]). A file that turns out to hold a video
/// ([isoMediaHasVideo]) is not played as sound: the card becomes a video card.
class AudioMessagePlayer extends StatefulWidget {
  final Attachment attachment;
  final AttachmentLoader loader;
  const AudioMessagePlayer({
    super.key,
    required this.attachment,
    required this.loader,
  });

  @override
  State<AudioMessagePlayer> createState() => _AudioMessagePlayerState();
}

class _AudioMessagePlayerState extends State<AudioMessagePlayer>
    with AttachmentSaving {
  final AudioPlayer _player = AudioPlayer();
  ChatAudioSource? _source;

  /// The bytes last checked for a video, and what they held. The answer is
  /// read from what [MediaCubit] holds on every build rather than kept here,
  /// since a card scrolled out of the list and back is a new one, and kept
  /// here it drew a found video as sound again.
  Uint8List? _checked;
  bool _checkedVideo = false;

  bool _holdsVideo(Uint8List? bytes) {
    if (bytes == null) return false;
    if (!identical(bytes, _checked)) {
      _checked = bytes;
      _checkedVideo = isoMediaHasVideo(bytes) == true;
    }
    return _checkedVideo;
  }

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
    final source = _source;
    _player.dispose().whenComplete(() => source?.release());
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
      return;
    }
    final ready = _source;
    if (ready != null) {
      await _player.resume();
      return;
    }
    setState(() => _loading = true);
    final data = await widget.loader(widget.attachment);
    final video = _holdsVideo(data);
    final source = data == null || video
        ? null
        : await ChatAudioSource.of(data, widget.attachment.mime);
    if (!mounted) {
      await source?.release();
      return;
    }
    setState(() {
      _source = source;
      _loading = false;
    });
    if (source != null) await _player.play(source.source);
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString();
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final held = context.select<MediaCubit, Uint8List?>(
      (c) => c.state
          .entry(MediaKind.attachment, widget.attachment.storagePath)
          ?.bytes,
    );
    if (_holdsVideo(held)) {
      return AttachmentVideoCard(
        attachment: widget.attachment,
        loader: widget.loader,
      );
    }
    final theme = context.theme;
    final total = _duration.inMilliseconds == 0 ? 1 : _duration.inMilliseconds;
    final progress = (_position.inMilliseconds / total).clamp(0.0, 1.0);

    return Container(
      constraints: const BoxConstraints(maxWidth: 300),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: theme.bgTertiary,
        borderRadius: BorderRadius.circular(K.radiusCard),
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
                  style: AppText.figure.copyWith(color: theme.textTertiary),
                ),
              ],
            ),
          ),
          _saveButton(),
        ],
      ),
    );
  }

  Widget _saveButton() {
    return Tooltip(
      message: 'Save',
      child: Material(
        type: MaterialType.transparency,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          onTap: () => saveFile(widget.loader, widget.attachment),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: SaveProgressGlyph(busy: savingNow, progress: saveProgress),
          ),
        ),
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
          width: K.compactControlHeight,
          height: K.compactControlHeight,
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
              ? Center(child: LoadingDots(color: theme.onPrimary, dotSize: 4))
              : Icon(
                  _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: theme.onPrimary,
                  size: K.iconButton,
                ),
        ),
      ),
    );
  }
}
