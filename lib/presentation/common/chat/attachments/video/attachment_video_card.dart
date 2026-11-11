import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/attachment.dart';
import '../../../../../data/constants.dart';
import '../../../../../data/repositories/blob/blob_reader.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/media/media_cubit.dart';
import '../../../../../logic/services/chat_clip/chat_clip.dart';
import '../../../../../src/rust/api/clips.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/media_colors.dart';
import '../attachment_file_card.dart';
import '../attachment_image_thumb.dart';
import '../attachment_loader.dart';
import '../attachment_saving.dart';
import 'widgets/video_middle.dart';
import 'widgets/video_seek_bar.dart';

/// A video attachment, played in the message list: a box the shape of the
/// video with its poster and a play disc, which downloads and plays it in
/// place.
///
/// The file is played from memory by [ChatClip], with the system's own
/// decoders: a big one fetched as it plays, a small one whole. Where this
/// build has no player the card is a file to save, and
/// where the system cannot decode what the file holds it says so and still
/// offers it.
class AttachmentVideoCard extends StatefulWidget {
  final Attachment attachment;
  final AttachmentLoader loader;

  const AttachmentVideoCard({
    super.key,
    required this.attachment,
    required this.loader,
  });

  @override
  State<AttachmentVideoCard> createState() => _AttachmentVideoCardState();
}

class _AttachmentVideoCardState extends State<AttachmentVideoCard>
    with AttachmentSaving {
  /// The box when neither the sender nor the player has said a shape.
  static const Size _fallback = Size(320, 180);

  ChatClip? _clip;
  StreamSubscription<ClipEvent>? _events;
  Timer? _ticker;
  bool _opening = false;
  bool _playing = false;
  bool _ended = false;
  String? _problem;
  Size? _picture;
  Duration _position = Duration.zero;
  late Duration _length = Duration(
    milliseconds: widget.attachment.durationMs ?? 0,
  );

  @override
  void initState() {
    super.initState();
    _wantPoster();
  }

  /// The first picture, to show until it plays: the poster the sender made
  /// and sealed beside the video, fetched as a picture attachment is. Not a
  /// byte of the video is fetched before play is pressed, so a video sent
  /// without one stays dark until then.
  void _wantPoster() {
    final poster = widget.attachment.poster;
    if (poster == null || !ChatClip.available) return;
    final loader = widget.loader;
    context.read<MediaCubit>().want(
      MediaKind.attachment,
      poster.storagePath,
      () => loader(poster),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _events?.cancel();
    _clip?.close();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_opening || _problem != null) return;
    final clip = _clip;
    if (clip == null) return _open();
    if (_playing) {
      await clip.pause();
      _setPlaying(false);
      return;
    }
    if (_ended) {
      await clip.seek(Duration.zero);
      setState(() {
        _ended = false;
        _position = Duration.zero;
      });
    }
    _setPlaying(await clip.play());
  }

  Future<void> _open() async {
    setState(() => _opening = true);
    final output = context.read<AppCubit>().state.outputDeviceId;
    final file = await _file();
    final reader = file.reader;
    if (!mounted) {
      await reader?.close();
      return;
    }
    if (reader == null) {
      setState(() {
        _opening = false;
        _problem = file.problem;
      });
      return;
    }
    final opened = await ChatClip.open(
      reader,
      output: output,
      type: widget.attachment.mime,
    );
    final clip = opened.clip;
    if (!mounted) {
      await clip?.close();
      return;
    }
    if (clip == null) {
      setState(() {
        _opening = false;
        _problem = 'This video could not be played.';
      });
      return;
    }
    _events = clip.events.listen(_heard);
    setState(() {
      _clip = clip;
      _opening = false;
    });
    _setPlaying(await clip.play());
  }

  /// What the player reads: the file fetched as it plays where it can be,
  /// or else the whole of it, when that is small enough to hold.
  Future<({BlobReader? reader, String? problem})> _file() async {
    final attachment = widget.attachment;
    final streamed = widget.loader.readerFor(attachment);
    if (streamed != null) return (reader: streamed, problem: null);
    if (attachment.size > ChatClip.wholeMaxBytes) {
      return (
        reader: null,
        problem: 'This video is too big to play here. Save it to watch it.',
      );
    }
    final bytes = await widget.loader(attachment);
    if (bytes == null) {
      return (reader: null, problem: 'This video could not be downloaded.');
    }
    return (reader: MemoryBlobReader(bytes), problem: null);
  }

  void _heard(ClipEvent event) {
    if (!mounted) return;
    switch (event.kind) {
      case ClipEventKind.pictureSize:
        setState(
          () =>
              _picture = Size(event.width.toDouble(), event.height.toDouble()),
        );
      case ClipEventKind.ended:
        _setPlaying(false);
        setState(() {
          _ended = true;
          _position = _length;
        });
      case ClipEventKind.cannotDecode:
        _fail(
          "This video's format doesn't play ${kIsWeb ? 'in this browser' : 'on this computer'}. "
          'Save it to watch it.',
        );
      case ClipEventKind.failed:
        _fail('This video could not be played.');
    }
  }

  void _fail(String why) {
    _setPlaying(false);
    _events?.cancel();
    _clip?.close();
    setState(() {
      _clip = null;
      _problem = why;
    });
  }

  /// Playing, and the time read while it is: the player has no clock of
  /// its own to send.
  void _setPlaying(bool playing) {
    if (!mounted) return;
    setState(() => _playing = playing);
    _ticker?.cancel();
    if (!playing) return;
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => _read());
  }

  void _read() {
    final time = _clip?.time();
    if (time == null || !mounted) return;
    setState(() {
      if (time.position != null) _position = time.position!;
      if (time.length != null && time.length! > Duration.zero) {
        _length = time.length!;
      }
    });
  }

  Future<void> _seek(Duration to) async {
    final clip = _clip;
    if (clip == null) return;
    setState(() {
      _position = to;
      _ended = false;
    });
    await clip.seek(to);
  }

  @override
  Widget build(BuildContext context) {
    if (!ChatClip.available) {
      return AttachmentFileCard(
        attachment: widget.attachment,
        loader: widget.loader,
      );
    }
    final posterPath = widget.attachment.poster?.storagePath;
    final poster = context.select<MediaCubit, Uint8List?>(
      (c) => posterPath == null
          ? null
          : c.state.entry(MediaKind.attachment, posterPath)?.bytes,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final shape = _picture;
        final box =
            AttachmentImageThumb.boxFor(
              shape?.width.round() ?? widget.attachment.width,
              shape?.height.round() ?? widget.attachment.height,
              within: constraints.maxWidth,
            ) ??
            _fallback;
        return SizedBox.fromSize(size: box, child: _card(poster));
      },
    );
  }

  Widget _card(Uint8List? poster) {
    final clip = _clip;
    final showsMiddle = !_playing || _opening || _problem != null;
    return ClipRRect(
      borderRadius: BorderRadius.circular(K.radiusCard),
      child: ColoredBox(
        color: MediaColors.videoGround,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Under the picture, so it shows until the first one lands.
            if (poster != null)
              Image.memory(poster, fit: BoxFit.contain, gaplessPlayback: true),
            if (clip != null && _picture != null) clip.picture(),
            Material(
              type: MaterialType.transparency,
              child: InkWell(
                mouseCursor: _problem == null
                    ? WidgetStateMouseCursor.clickable
                    : SystemMouseCursors.basic,
                onTap: _toggle,
                child: showsMiddle
                    ? Center(
                        child: VideoMiddle(
                          opening: _opening,
                          ended: _ended,
                          problem: _problem,
                        ),
                      )
                    : const SizedBox.expand(),
              ),
            ),
            if (clip != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: VideoSeekBar(
                  position: _position,
                  length: _length,
                  onSeek: _seek,
                ),
              )
            else if (_length > Duration.zero && _problem == null)
              Positioned(left: 8, bottom: 8, child: _lengthChip()),
            Positioned(top: 6, right: 6, child: _saveButton()),
          ],
        ),
      ),
    );
  }

  Widget _lengthChip() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: MediaColors.panel,
      borderRadius: BorderRadius.circular(K.radiusPill),
    ),
    child: Text(
      VideoSeekBar.clock(_length),
      style: AppText.figure.copyWith(color: MediaColors.onMedia),
    ),
  );

  Widget _saveButton() => Tooltip(
    message: 'Save',
    child: Material(
      color: MediaColors.panel,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        onTap: () => saveFile(widget.loader, widget.attachment),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: SaveProgressGlyph(
            busy: savingNow,
            progress: saveProgress,
            onMedia: true,
          ),
        ),
      ),
    ),
  );
}
