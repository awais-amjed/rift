import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../data/classes/attachment.dart';
import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/media/media_cubit.dart';
import '../../../../../logic/services/chat_clip/chat_clip.dart';
import '../../../../../logic/services/host_platform.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/media_colors.dart';
import '../attachment_file_card.dart';
import '../attachment_image_thumb.dart';
import '../attachment_loader.dart';
import '../attachment_saving.dart';
import 'clip_playback.dart';
import 'video_viewer_page.dart';
import 'widgets/video_controls.dart';
import 'widgets/video_middle.dart';

/// A video attachment, played in the message list: a box the shape of the
/// video with its poster and a play disc, which downloads and plays it in
/// place, with a strip to pause, seek, set the volume and make it bigger:
/// in the window or on the whole screen ([VideoViewerPage]).
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

  late final ClipPlayback _playback = ClipPlayback(
    attachment: widget.attachment,
    loader: widget.loader,
  )..addListener(_changed);
  AppLifecycleListener? _away;

  @override
  void initState() {
    super.initState();
    _wantPoster();
    _volumeFrom(context.read<AppCubit>().state);
    // On a phone a video stops when Rift goes out of sight (Home, another
    // app, the screen off) and waits there, as other chat apps do; on a
    // desktop or in a browser it plays on behind other windows.
    if (HostPlatform.isMobile) {
      _away = AppLifecycleListener(onHide: _playback.pause);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _volumeFrom(AppState app) =>
      _playback.setVolume(app.chatVideoMuted ? 0 : app.chatVideoVolume);

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
    _away?.dispose();
    _playback.removeListener(_changed);
    // On the full-screen page, it plays on there, and the page closes it.
    if (_playback.fullscreen) {
      _playback.cardGone = true;
    } else {
      _playback.dispose();
    }
    super.dispose();
  }

  void _toggle() =>
      _playback.toggle(output: context.read<AppCubit>().state.outputDeviceId);

  /// Bigger, playing: a press on the button of a video not yet started
  /// starts it too.
  void _open({required bool whole}) {
    if (_playback.clip == null) _toggle();
    VideoViewerPage.open(context, _playback, whole: whole);
  }

  void _fullscreen() => _open(whole: true);

  /// In the window, as a picture opens. A phone's window is its screen, so
  /// there full screen is the one way.
  VoidCallback? get _expand =>
      HostPlatform.isMobile ? null : () => _open(whole: false);

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
    return BlocListener<AppCubit, AppState>(
      listenWhen: (prev, curr) =>
          prev.chatVideoVolume != curr.chatVideoVolume ||
          prev.chatVideoMuted != curr.chatVideoMuted,
      listener: (_, app) => _volumeFrom(app),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final shape = _playback.picture;
          final box =
              AttachmentImageThumb.boxFor(
                shape?.width.round() ?? widget.attachment.width,
                shape?.height.round() ?? widget.attachment.height,
                within: constraints.maxWidth,
              ) ??
              _fallback;
          return SizedBox.fromSize(size: box, child: _card(poster));
        },
      ),
    );
  }

  Widget _card(Uint8List? poster) {
    final p = _playback;
    final clip = p.clip;
    // On the full-screen page instead: a web clip is one `<video>`, which
    // can be drawn in one place only.
    final away = p.fullscreen;
    final showsMiddle =
        !away && (!p.playing || p.opening || p.waiting || p.problem != null);
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
            if (clip != null && p.picture != null && !away) clip.picture(),
            Material(
              type: MaterialType.transparency,
              child: InkWell(
                mouseCursor: p.problem == null
                    ? WidgetStateMouseCursor.clickable
                    : SystemMouseCursors.basic,
                onTap: _toggle,
                child: showsMiddle
                    ? Center(
                        child: VideoMiddle(
                          loading: p.opening || p.waiting,
                          ended: p.ended,
                          problem: p.problem,
                        ),
                      )
                    : const SizedBox.expand(),
              ),
            ),
            if (clip != null && !away)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: VideoControls(
                  playback: p,
                  onToggle: _toggle,
                  big: false,
                  fullscreen: false,
                  onFullscreen: _fullscreen,
                  onExpand: _expand,
                ),
              )
            else if (p.length > Duration.zero && p.problem == null && !away)
              Positioned(left: 8, bottom: 8, child: _lengthChip()),
            Positioned(
              top: 6,
              right: 6,
              child: Row(
                spacing: 6,
                children: [
                  if (p.problem == null && clip == null && !p.opening) ...[
                    if (_expand case final expand?)
                      _roundButton(
                        tooltip: 'Expand',
                        onTap: expand,
                        child: const Icon(
                          Icons.open_in_full_rounded,
                          size: K.iconRow,
                          color: MediaColors.onMedia,
                        ),
                      ),
                    _roundButton(
                      tooltip: 'Full screen',
                      onTap: _fullscreen,
                      child: const Icon(
                        Icons.fullscreen_rounded,
                        size: K.iconRow,
                        color: MediaColors.onMedia,
                      ),
                    ),
                  ],
                  _roundButton(
                    tooltip: 'Save',
                    onTap: () => saveFile(widget.loader, widget.attachment),
                    child: SaveProgressGlyph(
                      busy: savingNow,
                      progress: saveProgress,
                      onMedia: true,
                    ),
                  ),
                ],
              ),
            ),
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
      VideoControls.clock(_playback.length),
      style: AppText.figure.copyWith(color: MediaColors.onMedia),
    ),
  );

  Widget _roundButton({
    required String tooltip,
    required VoidCallback onTap,
    required Widget child,
  }) => Tooltip(
    message: tooltip,
    child: Material(
      color: MediaColors.panel,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(6), child: child),
      ),
    ),
  );
}
