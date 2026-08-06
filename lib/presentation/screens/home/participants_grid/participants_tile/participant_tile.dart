import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../../../data/participant_identity.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../logic/services/participant_roster.dart';
import '../../../../../logic/services/participant_video.dart';
import '../../../../common/context_menu_region.dart';
import '../../sidebar/widgets/participant_context_menu.dart';
import 'collapsed_participant_tile.dart';
import 'expanded_participant_tile.dart';

/// One participant's video or avatar, in the grid or on the stage.
///
/// Owns the LiveKit listener that keeps the rendered track fresh, the
/// screenshare subscription, and the auto-hide timer for the expanded
/// overlays. The two layouts are [CollapsedParticipantTile] and
/// [ExpandedParticipantTile].
class ParticipantTileWidget extends StatefulWidget {
  final Participant participant;
  final bool isMuted;
  final VoidCallback? onTap;
  final bool isExpanded;

  const ParticipantTileWidget({
    super.key,
    required this.participant,
    this.isMuted = false,
    this.onTap,
    this.isExpanded = false,
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

  bool get _isScreenshare =>
      ParticipantIdentity.isScreenshare(widget.participant.identity);

  @override
  void initState() {
    super.initState();
    _updateVideoTrack();
    widget.participant.addListener(_onParticipantChanged);

    if (widget.isExpanded) _scheduleHide();

    if (_isScreenshare) {
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

  Future<void> _subscribeToScreenshare() => context
      .read<LiveKitCubit>()
      .subscribeToScreenshare(widget.participant.identity);

  Future<void> _unsubscribeFromScreenshare() => context
      .read<LiveKitCubit>()
      .unsubscribeFromScreenshare(widget.participant.identity);

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LiveKitCubit, LiveKitState>(
      builder: (context, livekitState) {
        // Camera tiles are always "subscribed"; only screenshares are opt-in.
        final isSubscribed =
            !_isScreenshare ||
            livekitState.subscribedScreenshares.contains(
              widget.participant.identity,
            );

        return BlocBuilder<ThemeCubit, ThemeState>(
          builder: (context, themeState) {
            final track = isSubscribed ? _videoPub?.track : null;
            final videoTrack = track is VideoTrack ? track : null;
            final showStopButton =
                _isScreenshare && isSubscribed && videoTrack != null;
            final name = widget.participant.name;

            return ContextMenuRegion(
              contextMenu: ParticipantContextMenu(
                identity: widget.participant.identity,
                name: name,
                isLocal: widget.participant is LocalParticipant,
              ),
              child: GestureDetector(
                onTap: widget.onTap,
                behavior: HitTestBehavior.opaque,
                child: widget.isExpanded
                    ? ExpandedParticipantTile(
                        themeState: themeState,
                        videoTrack: videoTrack,
                        name: name,
                        identity: widget.participant.identity,
                        isMicEnabled: widget.participant.isMicrophoneEnabled(),
                        isMuted: widget.isMuted,
                        isScreenshare: _isScreenshare,
                        showWatchButton: _isScreenshare && !isSubscribed,
                        showStopButton: showStopButton,
                        showOverlays: _showOverlays,
                        statsPinned: _statsPinned,
                        onActivity: _onActivity,
                        onWatch: _subscribeToScreenshare,
                        onStopWatching: _unsubscribeFromScreenshare,
                        onStatsPinnedChanged: _onStatsPinnedChanged,
                      )
                    : _buildCollapsed(
                        themeState: themeState,
                        videoTrack: videoTrack,
                        name: name,
                        isSubscribed: isSubscribed,
                        showStopButton: showStopButton,
                      ),
              ),
            );
          },
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
          themeState: themeState,
          videoTrack: videoTrack,
          isSpeaking: isSpeaking && !widget.isMuted,
          name: name,
          identity: widget.participant.identity,
          isMicEnabled: widget.participant.isMicrophoneEnabled(),
          isMuted: widget.isMuted,
          isScreenshare: _isScreenshare,
          showWatchButton: _isScreenshare && !isSubscribed,
          showStopButton: showStopButton,
          onWatch: _subscribeToScreenshare,
          onStopWatching: _unsubscribeFromScreenshare,
        );
      },
    );
  }
}
