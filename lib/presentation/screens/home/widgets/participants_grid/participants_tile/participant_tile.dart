import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../common/context_menu_region.dart';
import '../../../../../theme/custom_colors.dart';
import '../../sidebar/widgets/participant_context_menu.dart';
import 'avatar_placeholder.dart';
import 'participant_name_badge.dart';
import 'stop_watching_button.dart';
import 'stream_stats_overlay.dart';
import 'watch_stream_button.dart';

/// Displays a single participant's video or avatar fallback tile.
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
  TrackPublication? _videoPub;
  bool _isSpeaking = false;
  bool _showOverlays = true;
  Timer? _hideTimer;

  static const _hideDelay = Duration(seconds: 2);

  bool get _isScreenshare =>
      widget.participant.identity.endsWith('_screenshare');

  @override
  void initState() {
    super.initState();
    _updateVideoTrack();
    widget.participant.addListener(_onParticipantChanged);

    // Schedule auto-hide if expanded
    if (widget.isExpanded) {
      _scheduleHide();
    }

    // Unsubscribe from screenshare on first load
    if (_isScreenshare) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final livekitCubit = context.read<LiveKitCubit>();
          final isSubscribed = livekitCubit.state.subscribedScreenshares
              .contains(widget.participant.identity);
          if (isSubscribed) {
            // Already subscribed from previous state, keep it
          } else {
            // Not subscribed, make sure it stays unsubscribed
            livekitCubit.unsubscribeFromScreenshare(
              widget.participant.identity,
            );
          }
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

    // Handle expansion state changes
    if (oldWidget.isExpanded != widget.isExpanded) {
      if (widget.isExpanded) {
        // Just expanded, show overlays and schedule hide
        setState(() => _showOverlays = true);
        _scheduleHide();
      } else {
        // Collapsed, cancel hide timer and show overlays
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
    if (mounted) {
      setState(() {
        _updateVideoTrack();
        _isSpeaking = widget.participant.isSpeaking;
      });
    }
  }

  void _updateVideoTrack() {
    if (_isScreenshare) {
      // For screenshare participants, look for screen share video track
      _videoPub = widget.participant.videoTrackPublications
          .where(
            (t) => t.source == TrackSource.screenShareVideo && t.track != null,
          )
          .cast<TrackPublication?>()
          .firstOrNull;
    } else {
      // For regular participants, look for camera video track
      _videoPub = widget.participant.videoTrackPublications
          .where(
            (t) =>
                t.source == TrackSource.camera && t.track != null && !t.muted,
          )
          .cast<TrackPublication?>()
          .firstOrNull;
    }
    _isSpeaking = widget.participant.isSpeaking;
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_hideDelay, () {
      if (mounted && widget.isExpanded) {
        setState(() => _showOverlays = false);
      }
    });
  }

  void _onActivity() {
    if (widget.isExpanded) {
      if (!_showOverlays) {
        setState(() => _showOverlays = true);
      }
      _scheduleHide();
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LiveKitCubit, LiveKitState>(
      builder: (context, livekitState) {
        // Check if this screenshare is subscribed from the persistent state
        final isSubscribed = _isScreenshare
            ? livekitState.subscribedScreenshares.contains(
                widget.participant.identity,
              )
            : true; // Regular video is always auto-subscribed

        return BlocBuilder<ThemeCubit, ThemeState>(
          builder: (context, themeState) {
            final hasVideo = _videoPub != null && isSubscribed;
            final isSpeaking = _isSpeaking && !widget.isMuted;
            final name = widget.participant.name;
            final showWatchButton = _isScreenshare && !isSubscribed;
            final showStopButton = _isScreenshare && isSubscribed && hasVideo;

            final content = GestureDetector(
              onTap: widget.onTap,
              behavior: HitTestBehavior.opaque,
              child: widget.isExpanded
                  ? Listener(
                      behavior: HitTestBehavior.translucent,
                      onPointerMove: (_) => _onActivity(),
                      onPointerHover: (_) => _onActivity(),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // Video or avatar
                          if (hasVideo && _videoPub!.track is VideoTrack)
                            VideoTrackRenderer(
                              _videoPub!.track as VideoTrack,
                              fit: VideoViewFit.contain,
                            )
                          else
                            AvatarPlaceholder(
                              name: name,
                              isDark: themeState.isDarkTheme,
                            ),
                          // Stream stats overlay at top right (for screenshare with video)
                          if (showStopButton &&
                              _videoPub!.track is VideoTrack &&
                              _showOverlays)
                            StreamStatsOverlay(
                              track: _videoPub!.track as VideoTrack,
                            ),
                          // Watch Stream button for unsubscribed screenshare
                          if (showWatchButton)
                            WatchStreamButton(
                              onTap: () => _subscribeToScreenshare(context),
                            ),
                          // Stop Watching button at bottom right for subscribed screenshare
                          if (showStopButton)
                            Positioned(
                              bottom: 12,
                              right: 12,
                              child: AnimatedOpacity(
                                opacity: _showOverlays ? 1.0 : 0.0,
                                duration: const Duration(milliseconds: 300),
                                child: IgnorePointer(
                                  ignoring: !_showOverlays,
                                  child: StopWatchingButton(
                                    onTap: () =>
                                        _unsubscribeFromScreenshare(context),
                                  ),
                                ),
                              ),
                            ),
                          // Name + mic badge (hide for screenshare with watch button)
                          if (!showWatchButton)
                            Positioned(
                              bottom: 12,
                              left: 12,
                              child: AnimatedOpacity(
                                opacity: _showOverlays ? 1.0 : 0.0,
                                duration: const Duration(milliseconds: 300),
                                child: ParticipantNameBadge(
                                  name: name,
                                  isMicEnabled: widget.participant
                                      .isMicrophoneEnabled(),
                                  isMuted: widget.isMuted,
                                  isScreenshare: _isScreenshare,
                                ),
                              ),
                            ),
                        ],
                      ),
                    )
                  : AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        color: themeState.isDarkTheme
                            ? CustomColors.bgSecondaryDark
                            : CustomColors.bgTertiaryLight,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSpeaking
                              ? CustomColors.primary
                              : themeState.borderPrimary,
                          width: isSpeaking ? 2 : 1,
                        ),
                        boxShadow: isSpeaking
                            ? [
                                BoxShadow(
                                  color: CustomColors.primary.withValues(
                                    alpha: 0.3,
                                  ),
                                  blurRadius: 12,
                                  spreadRadius: 2,
                                ),
                              ]
                            : null,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(13),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // Video or avatar
                            if (hasVideo && _videoPub!.track is VideoTrack)
                              VideoTrackRenderer(
                                _videoPub!.track as VideoTrack,
                                fit: VideoViewFit.contain,
                              )
                            else
                              AvatarPlaceholder(
                                name: name,
                                isDark: themeState.isDarkTheme,
                              ),
                            // Watch Stream button for unsubscribed screenshare
                            if (showWatchButton)
                              WatchStreamButton(
                                onTap: () => _subscribeToScreenshare(context),
                              ),
                            // Stop Watching button at bottom right for subscribed screenshare
                            if (showStopButton)
                              Positioned(
                                bottom: 12,
                                right: 12,
                                child: StopWatchingButton(
                                  onTap: () =>
                                      _unsubscribeFromScreenshare(context),
                                ),
                              ),
                            // Name + mic badge (hide for screenshare with watch button)
                            if (!showWatchButton)
                              Positioned(
                                bottom: 12,
                                left: 12,
                                child: ParticipantNameBadge(
                                  name: name,
                                  isMicEnabled: widget.participant
                                      .isMicrophoneEnabled(),
                                  isMuted: widget.isMuted,
                                  isScreenshare: _isScreenshare,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
            );

            if (widget.participant is LocalParticipant) {
              return ContextMenuRegion(
                contextMenu: ParticipantContextMenu(
                  identity: widget.participant.identity,
                  name: name,
                  isLocal: true,
                ),
                child: content,
              );
            }

            return ContextMenuRegion(
              contextMenu: ParticipantContextMenu(
                identity: widget.participant.identity,
                name: name,
              ),
              child: content,
            );
          },
        );
      },
    );
  }

  Future<void> _subscribeToScreenshare(BuildContext context) async {
    final livekitCubit = context.read<LiveKitCubit>();
    await livekitCubit.subscribeToScreenshare(widget.participant.identity);
  }

  Future<void> _unsubscribeFromScreenshare(BuildContext context) async {
    final livekitCubit = context.read<LiveKitCubit>();
    await livekitCubit.unsubscribeFromScreenshare(widget.participant.identity);
  }
}
