import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../../../data/participant_identity.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../../logic/cubits/server_members/server_members_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../logic/services/participant_roster.dart';
import '../../../../../logic/services/participant_video.dart';
import '../../../../common/context_menu_region.dart';
import '../../../../theme/theme_context.dart';
import '../../sidebar/widgets/participant_context_menu.dart';
import 'collapsed_participant_tile.dart';
import 'expanded_participant_tile.dart';
import 'stream_context_menu.dart';

/// Over the widget budget and one job: one participant's tile. The grid and
/// stage layouts are already their own widgets; what is left is the state they
/// share.
///
/// One participant's video or avatar, in the grid or on the stage.
///
/// Owns the LiveKit listener that keeps the rendered track fresh, the
/// screenshare subscription, and the auto-hide timer for the expanded
/// overlays. The two layouts are [CollapsedParticipantTile] and
/// [ExpandedParticipantTile].
class ParticipantTileWidget extends StatefulWidget {
  final Participant participant;

  /// Whether this cell shows the participant's *screen* rather than the
  /// participant. Passed in rather than read off the identity: a phone
  /// publishes its screen on the connection it already has, so one identity
  /// can own both kinds of cell. See `voiceTilesFor`.
  final bool isScreenshare;

  final bool isMuted;
  final VoidCallback? onTap;
  final bool isExpanded;

  /// Called once the viewer has asked to watch this screen share, and once
  /// they have asked to stop. The grid uses them to take the share in and
  /// out of focus.
  final VoidCallback? onWatchStarted;
  final VoidCallback? onWatchStopped;

  /// Told the shape of the grid tile's video. See [ShapeReportingVideo].
  final ValueChanged<double>? onAspectRatio;

  /// See [ExpandedParticipantTile.topInset].
  final double topInset;

  /// See [ExpandedParticipantTile.bottomInset].
  final double bottomInset;

  const ParticipantTileWidget({
    super.key,
    required this.participant,
    required this.isScreenshare,
    this.isMuted = false,
    this.onTap,
    this.isExpanded = false,
    this.onWatchStarted,
    this.onWatchStopped,
    this.onAspectRatio,
    this.topInset = 0,
    this.bottomInset = 0,
  });

  @override
  State<ParticipantTileWidget> createState() => _ParticipantTileWidgetState();
}

class _ParticipantTileWidgetState extends State<ParticipantTileWidget> {
  /// How long the expanded overlays stay up after the pointer stops moving.
  static const _hideDelay = Duration(seconds: 2);

  TrackPublication? _videoPub;
  bool _showOverlays = true;
  bool _statsPinned = false;
  Timer? _hideTimer;

  bool get _isScreenshare => widget.isScreenshare;

  @override
  void initState() {
    super.initState();
    _updateVideoTrack();
    widget.participant.addListener(_onParticipantChanged);

    if (widget.isExpanded) _scheduleHide();

    // Nothing to arrange for your own screen: the track is local, already in
    // hand, and there is no subscription to hold off.
    if (_isScreenshare && widget.participant is! LocalParticipant) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final livekitCubit = context.read<LiveKitCubit>();
        if (!livekitCubit.state.subscribedScreenshares.contains(
          widget.participant.identity,
        )) {
          livekitCubit.unsubscribeFromScreenshare(widget.participant.identity);
        }
      });
    }
  }

  @override
  void didUpdateWidget(ParticipantTileWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.participant != widget.participant) {
      oldWidget.participant.removeListener(_onParticipantChanged);
      widget.participant.addListener(_onParticipantChanged);
    }

    if (oldWidget.isExpanded != widget.isExpanded) {
      if (widget.isExpanded) {
        setState(() => _showOverlays = true);
        _scheduleHide();
      } else {
        _hideTimer?.cancel();
        setState(() => _showOverlays = true);
      }
    }
  }

  @override
  void dispose() {
    widget.participant.removeListener(_onParticipantChanged);
    _hideTimer?.cancel();
    super.dispose();
  }

  void _onParticipantChanged() {
    if (mounted) setState(_updateVideoTrack);
  }

  void _updateVideoTrack() {
    _videoPub = ParticipantVideo.activePublication(
      widget.participant.videoTrackPublications,
      isScreenshare: _isScreenshare,
    );
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (_statsPinned) return;
    _hideTimer = Timer(_hideDelay, () {
      if (mounted && widget.isExpanded) {
        setState(() => _showOverlays = false);
      }
    });
  }

  /// Any pointer movement over the stage brings the overlays back and
  /// restarts the countdown.
  void _onActivity() {
    if (!widget.isExpanded) return;
    if (!_showOverlays) setState(() => _showOverlays = true);
    _scheduleHide();
  }

  void _onStatsPinnedChanged(bool pinned) {
    setState(() {
      _statsPinned = pinned;
      if (pinned) _showOverlays = true;
    });
    if (pinned) {
      _hideTimer?.cancel();
    } else {
      _scheduleHide();
    }
  }

  Future<void> _subscribeToScreenshare() {
    widget.onWatchStarted?.call();
    return context.read<LiveKitCubit>().subscribeToScreenshare(
      widget.participant.identity,
    );
  }

  Future<void> _unsubscribeFromScreenshare() {
    widget.onWatchStopped?.call();
    return context.read<LiveKitCubit>().unsubscribeFromScreenshare(
      widget.participant.identity,
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LiveKitCubit, LiveKitState>(
      builder: (context, livekitState) {
        // Read again on every rebuild, not only when the participant says it
        // changed: a stream opened full size builds this tile before its track
        // arrives, and the arrival did not reach it — it stayed on the avatar.
        _updateVideoTrack();
        // Camera tiles are always "subscribed"; streams are opt-in, your own
        // included. A desktop's comes back as a connection like anyone
        // else's; a phone's is a local track, but it is hidden and shown the
        // same way, or a phone could not put its own stream away.
        final isSubscribed =
            !_isScreenshare ||
            livekitState.subscribedScreenshares.contains(
              widget.participant.identity,
            );

        final themeState = context.theme;
        final track = isSubscribed ? _videoPub?.track : null;
        final videoTrack = track is VideoTrack ? track : null;
        final showStopButton =
            _isScreenshare && isSubscribed && videoTrack != null;
        // The identity carries a device segment (and a screenshare
        // suffix), so everything about the *person* — their name, their
        // gradient — keys off the user id inside it instead.
        final userId = ParticipantIdentity.userIdOf(
          widget.participant.identity,
        );
        // `participant.name` is the display name frozen into the LiveKit
        // token at mint time, and tokens are cached for their full hour —
        // so a rename mid-call left the old name on the tile even after a
        // reconnect. The roster is the live copy.
        final name = context.watch<ServerMembersCubit>().state.nameFor(
          userId,
          widget.participant.name,
        );
        final isDeafened = context.select<AppCubit, bool>(
          (cubit) => ParticipantRoster.isDeafened(
            cubit.state.participants,
            widget.participant.identity,
          ),
        );
        // Only ever true for a screen share's own connection.
        final isPaused = context.select<AppCubit, bool>(
          (cubit) => ParticipantRoster.isSharePaused(
            cubit.state.participants,
            widget.participant.identity,
          ),
        );

        // A stream opens a menu for its sound — your own desktop's too,
        // since it comes back to you as a connection with its sound on it.
        // A phone's own stream is a local track with no sound coming back,
        // so its menu is still you.
        final isPhoneOwnStream = widget.participant is LocalParticipant;
        // An unopened stream has nothing to focus but a button, so the
        // whole tile is the button. A click on the button itself only
        // focused the tile, and a second one was needed to watch.
        final opensStream = _isScreenshare && !isSubscribed;
        final onTap = opensStream ? _subscribeToScreenshare : widget.onTap;
        return ContextMenuRegion(
          contextMenu: _isScreenshare && !isPhoneOwnStream
              ? StreamContextMenu(
                  identity: widget.participant.identity,
                  ownerName: name,
                )
              : ParticipantContextMenu(
                  identity: widget.participant.identity,
                  name: name,
                  isLocal: widget.participant is LocalParticipant,
                ),
          child: MouseRegion(
            cursor: onTap != null
                ? SystemMouseCursors.click
                : MouseCursor.defer,
            child: GestureDetector(
              onTap: onTap,
              behavior: HitTestBehavior.opaque,
              child: widget.isExpanded
                  ? ExpandedParticipantTile(
                      videoTrack: videoTrack,
                      name: name,
                      userId: userId,
                      isMicEnabled: widget.participant.isMicrophoneEnabled(),
                      isMuted: widget.isMuted,
                      isDeafened: isDeafened,
                      isScreenshare: _isScreenshare,
                      isPaused: isPaused,
                      showWatchButton: _isScreenshare && !isSubscribed,
                      showStopButton: showStopButton,
                      showOverlays: _showOverlays,
                      statsPinned: _statsPinned,
                      onActivity: _onActivity,
                      onWatch: _subscribeToScreenshare,
                      onStopWatching: _unsubscribeFromScreenshare,
                      onStatsPinnedChanged: _onStatsPinnedChanged,
                      topInset: widget.topInset,
                      bottomInset: widget.bottomInset,
                    )
                  : _buildCollapsed(
                      themeState: themeState,
                      videoTrack: videoTrack,
                      name: name,
                      userId: userId,
                      isDeafened: isDeafened,
                      isPaused: isPaused,
                      isSubscribed: isSubscribed,
                      showStopButton: showStopButton,
                    ),
            ),
          ),
        );
      },
    );
  }

  /// The grid tile, which is the only layout that glows while its owner talks.
  ///
  /// Speaking comes from the published roster rather than from
  /// `participant.isSpeaking`, so this tile and the same person's row in the
  /// sidebar light up together. See [ParticipantRoster.isSpeaking].
  Widget _buildCollapsed({
    required ThemeState themeState,
    required VideoTrack? videoTrack,
    required String name,
    required String userId,
    required bool isDeafened,
    required bool isPaused,
    required bool isSubscribed,
    required bool showStopButton,
  }) {
    return BlocSelector<AppCubit, AppState, bool>(
      selector: (appState) => ParticipantRoster.isSpeaking(
        appState.participants,
        widget.participant.identity,
        fallback: widget.participant.isSpeaking,
      ),
      builder: (context, isSpeaking) {
        return CollapsedParticipantTile(
          videoTrack: videoTrack,
          isSpeaking: isSpeaking && !widget.isMuted,
          name: name,
          userId: userId,
          isMicEnabled: widget.participant.isMicrophoneEnabled(),
          isMuted: widget.isMuted,
          isDeafened: isDeafened,
          isScreenshare: _isScreenshare,
          isPaused: isPaused,
          showWatchButton: _isScreenshare && !isSubscribed,
          showStopButton: showStopButton,
          onWatch: _subscribeToScreenshare,
          onStopWatching: _unsubscribeFromScreenshare,
          onAspectRatio: widget.onAspectRatio,
        );
      },
    );
  }
}
