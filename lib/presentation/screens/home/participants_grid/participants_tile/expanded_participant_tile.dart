import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../../../data/enums/stream_pip_corner.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/services/video_stream_stats.dart';
import '../../../../theme/app_motion.dart';
import 'avatar_placeholder.dart';
import 'decrypted_video.dart';
import 'participant_name_badge.dart';
import 'share_paused_notice.dart';
import 'stream_camera_pip.dart';
import 'stream_quality_badge.dart';
import 'stream_stats_overlay.dart';
import 'stream_stats_poller.dart';
import 'stream_view.dart';
import 'stream_view_buttons.dart';
import 'stream_watchers.dart';
import 'watch_stream_button.dart';

/// Over the widget budget and one job: one participant on the stage, with its
/// overlays.
///
/// A participant filling the stage. Same content as the grid tile without the
/// card chrome, plus a stats overlay and controls that fade out while the
/// pointer is still — [showOverlays] drives that, and pointer activity is
/// reported through [onActivity].
class ExpandedParticipantTile extends StatelessWidget {
  static const _fade = AppMotion.enter;

  final VideoTrack? videoTrack;
  final String name;

  /// The *user* id, which picks the avatar's gradient so a participant looks
  /// the same here as in the sidebar. Not the LiveKit identity: that carries a
  /// device segment, so seeding with it gave the same person a different
  /// colour here, and a third one again for their screenshare.
  final String userId;
  final bool isMicEnabled;
  final bool isMuted;

  /// See [ParticipantNameBadge.isPushToTalkIdle].
  final bool isPushToTalkIdle;
  final bool isDeafened;
  final bool isScreenshare;

  /// The stream's identity, for showing who is watching it ([StreamWatchers]).
  /// Null on a camera tile.
  final String? shareIdentity;

  /// The stream's shared window is minimised or gone, so the picture is the
  /// last frame, or there is none yet — see [SharePausedNotice].
  final bool isPaused;

  /// What the sharer says the stream is sent at ("1080p · 60fps"), which the
  /// badge shows in place of the measured rate. Null for anything else.
  final String? sentQuality;
  final bool showWatchButton;

  /// Someone else's stream with its picture here: the one thing that has
  /// receive stats to poll. Stopping it is the call bar's job, where Leave
  /// turns into Stop watching.
  final bool isWatching;

  /// How the stream is shown. On a page of its own, edge to edge or full
  /// screen, the pointer hides along with the overlays — a film does.
  final StreamView view;

  /// Asks for edge to edge or full screen, or out of the one it is in. Null
  /// for anything that has no buttons for it: only a stream being watched
  /// does.
  final ValueChanged<StreamView>? onView;

  /// See [StreamViewButtons.soundKey].
  final String? soundKey;

  /// The sharer's camera, floated over the stream they are sharing
  /// ([StreamCameraPip]). Null on anything else, or with their camera off.
  final VideoTrack? ownerCamera;
  final bool showOverlays;
  final bool statsPinned;
  final VoidCallback onActivity;
  final VoidCallback onWatch;
  final ValueChanged<bool> onStatsPinnedChanged;

  /// How much of the top edge something else is covering right now — the
  /// call's top bar floating over the stage. The stats move down past it.
  final double topInset;

  /// How much of the bottom edge the call controls cover right now. The
  /// badges in the bottom corners move up past it, but only on a stage too
  /// narrow for them to sit beside the controls — on a wide one they would
  /// just be lifted into the middle of the picture for nothing.
  final double bottomInset;

  /// Narrower than this and the controls, centred, reach the corners.
  static const _crowdedWidth = 900.0;

  /// What the row of badges or buttons along the foot takes, with a gap:
  /// the sharer's camera rises above it while it shows.
  static const _footRoom = 40.0;

  /// What who is watching ([StreamWatchers]) takes at the head, with a gap:
  /// the camera sits below it there while it shows.
  static const _headRoom = 38.0;

  const ExpandedParticipantTile({
    super.key,
    required this.videoTrack,
    required this.name,
    required this.userId,
    required this.isMicEnabled,
    required this.isMuted,
    this.isPushToTalkIdle = false,
    this.isDeafened = false,
    required this.isScreenshare,
    this.shareIdentity,
    this.isPaused = false,
    this.sentQuality,
    required this.showWatchButton,
    required this.isWatching,
    this.view = StreamView.inCall,
    this.onView,
    this.soundKey,
    this.ownerCamera,
    required this.showOverlays,
    required this.statsPinned,
    required this.onActivity,
    required this.onWatch,
    required this.onStatsPinnedChanged,
    this.topInset = 0,
    this.bottomInset = 0,
  });

  /// Wraps an overlay so it fades out *and* stops taking pointer events —
  /// an invisible button that still swallows clicks is worse than no button.
  Widget _fading({required bool visible, required Widget child}) =>
      AnimatedOpacity(
        opacity: visible ? 1.0 : 0.0,
        duration: _fade,
        child: IgnorePointer(ignoring: !visible, child: child),
      );

  @override
  Widget build(BuildContext context) {
    final showStats = context.select<AppCubit, bool>(
      (c) => c.state.showStreamStats,
    );
    final pipCorner = context.select<AppCubit, StreamPipCorner>(
      (c) => c.state.streamPipCorner,
    );
    final pipHidden = context.select<AppCubit, bool>(
      (c) => c.state.streamPipHidden,
    );
    final pipScale = context.select<AppCubit, double>(
      (c) => c.state.streamPipScale,
    );
    final camera = isWatching ? ownerCamera : null;
    final listener = Listener(
      behavior: HitTestBehavior.translucent,
      onPointerMove: (_) => onActivity(),
      onPointerHover: (_) => onActivity(),
      // A phone has no hover, and a tap is no move: its overlays went for
      // good two seconds in, while the call's own controls came back.
      onPointerDown: (_) => onActivity(),
      // Only someone else's share you are watching has receive stats.
      child: LayoutBuilder(
        builder: (context, constraints) {
          final lift = constraints.maxWidth < _crowdedWidth ? bottomInset : 0.0;
          return StreamStatsPoller(
            track: isWatching ? videoTrack : null,
            builder: (context, stats) => _stage(
              context,
              stats,
              showStats: showStats,
              bottom: 12 + lift,
              stage: constraints.biggest,
              camera: camera,
              pipCorner: pipCorner,
              pipHidden: pipHidden,
              pipScale: pipScale,
            ),
          );
        },
      ),
    );
    if (!view.isAlone) return listener;
    return MouseRegion(
      cursor: showOverlays ? MouseCursor.defer : SystemMouseCursors.none,
      child: listener,
    );
  }

  Widget _stage(
    BuildContext context,
    VideoStreamStats? stats, {
    required bool showStats,
    required double bottom,
    required Size stage,
    required VideoTrack? camera,
    required StreamPipCorner pipCorner,
    required bool pipHidden,
    required double pipScale,
  }) {
    final pip = pipHidden ? null : camera;
    // In the top right the camera goes between who is watching and the
    // stats: the stats make way for it below the watchers.
    final pipTopRight = pip != null && pipCorner == StreamPipCorner.topRight;
    final app = context.read<AppCubit>();
    return Stack(
      fit: StackFit.expand,
      children: [
        if (videoTrack != null)
          DecryptedVideo(
            track: videoTrack!,
            child: VideoTrackRenderer(videoTrack!, fit: VideoViewFit.contain),
          )
        else if (!showWatchButton && !isPaused)
          AvatarPlaceholder(name: name, userId: userId),
        // Over the last frame, or in place of a first one: a share started
        // on a minimised window has no picture until the window is opened.
        if (isPaused && !showWatchButton) const SharePausedNotice(),
        AnimatedPositioned(
          duration: _fade,
          curve: Curves.easeInOut,
          top: 12 + topInset,
          right: 12,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            spacing: 8,
            children: [
              if (shareIdentity case final share?)
                _fading(
                  visible: showOverlays,
                  child: StreamWatchers(shareIdentity: share),
                ),
              if (pipTopRight)
                SizedBox(
                  height: StreamCameraPip.sizeFor(stage, pipScale).height,
                ),
              if (showStats && stats != null)
                // Pinned stats stay put even after the other overlays fade.
                _fading(
                  visible: showOverlays || statsPinned,
                  child: StreamStatsOverlay(
                    stats: stats,
                    onPinnedChanged: onStatsPinnedChanged,
                  ),
                ),
            ],
          ),
        ),
        if (showWatchButton) WatchStreamButton(onTap: onWatch),
        if (pip != null)
          StreamCameraPip(
            track: pip,
            corner: pipCorner,
            scale: pipScale,
            stage: stage,
            margin: EdgeInsets.fromLTRB(
              12,
              // Below who is watching while they show, in the top right.
              12 + topInset + (pipTopRight && showOverlays ? _headRoom : 0),
              12,
              // Above the badges and buttons while they show; into the
              // corner itself once they fade.
              bottom + (showOverlays ? _footRoom : 0),
            ),
            onCorner: app.setStreamPipCorner,
            onScale: app.setStreamPipScale,
            showGrip: showOverlays,
          ),
        AnimatedPositioned(
          duration: _fade,
          curve: Curves.easeInOut,
          bottom: bottom,
          left: 12,
          right: 12,
          child: Align(
            alignment: Alignment.bottomLeft,
            child: _fading(
              visible: showOverlays,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 6,
                children: [
                  Flexible(
                    child: ParticipantNameBadge(
                      name: name,
                      isMicEnabled: isMicEnabled,
                      isMuted: isMuted,
                      isPushToTalkIdle: isPushToTalkIdle,
                      isDeafened: isDeafened,
                      isScreenshare: isScreenshare,
                    ),
                  ),
                  StreamQualityBadge(stats: stats, sent: sentQuality),
                ],
              ),
            ),
          ),
        ),
        if (onView != null)
          AnimatedPositioned(
            duration: _fade,
            curve: Curves.easeInOut,
            bottom: bottom,
            right: 12,
            child: _fading(
              visible: showOverlays,
              child: StreamViewButtons(
                view: view,
                onView: onView!,
                soundKey: soundKey,
                cameraShown: pip != null,
                onCamera: camera == null
                    ? null
                    : () => app.setStreamPipHidden(!pipHidden),
              ),
            ),
          ),
      ],
    );
  }
}
