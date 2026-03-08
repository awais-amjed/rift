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
import 'watch_stream_button.dart';

/// Displays a single participant's video or avatar fallback tile.
class ParticipantTileWidget extends StatefulWidget {
  final Participant participant;
  final bool isMuted;

  const ParticipantTileWidget({
    super.key,
    required this.participant,
    this.isMuted = false,
  });

  @override
  State<ParticipantTileWidget> createState() => _ParticipantTileWidgetState();
}

class _ParticipantTileWidgetState extends State<ParticipantTileWidget> {
  TrackPublication? _videoPub;
  bool _isSpeaking = false;
  bool _isSubscribed = false;
  bool _hasInitialized = false;

  bool get _isScreenshare =>
      widget.participant.identity.endsWith('_screenshare');

  @override
  void initState() {
    super.initState();
    _updateVideoTrack();
    widget.participant.addListener(_onParticipantChanged);

    // Unsubscribe from screenshare on first load
    if (_isScreenshare) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_hasInitialized) {
          _hasInitialized = true;
          final livekitCubit = context.read<LiveKitCubit>();
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
    _updateVideoTrack();
  }

  @override
  void dispose() {
    widget.participant.removeListener(_onParticipantChanged);
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

      // Check if subscribed
      _isSubscribed = _videoPub?.subscribed ?? false;
    } else {
      // For regular participants, look for camera video track
      _videoPub = widget.participant.videoTrackPublications
          .where(
            (t) =>
                t.source == TrackSource.camera && t.track != null && !t.muted,
          )
          .cast<TrackPublication?>()
          .firstOrNull;
      _isSubscribed = true; // Regular video is always auto-subscribed
    }
    _isSpeaking = widget.participant.isSpeaking;
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        final hasVideo = _videoPub != null && _isSubscribed;
        final isSpeaking = _isSpeaking && !widget.isMuted;
        final name = widget.participant.name;
        final showWatchButton = _isScreenshare && !_isSubscribed;
        final showStopButton = _isScreenshare && _isSubscribed && hasVideo;

        final content = AnimatedContainer(
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
                      color: CustomColors.primary.withValues(alpha: 0.3),
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
                  AvatarPlaceholder(name: name, isDark: themeState.isDarkTheme),
                // Watch Stream button for unsubscribed screenshare
                if (showWatchButton)
                  WatchStreamButton(
                    onTap: () => _subscribeToScreenshare(context),
                  ),
                // Stop Watching button for subscribed screenshare
                if (showStopButton)
                  Positioned(
                    top: 12,
                    right: 12,
                    child: StopWatchingButton(
                      onTap: () => _unsubscribeFromScreenshare(context),
                    ),
                  ),
                // Name + mic badge (hide for screenshare with watch button)
                if (!showWatchButton)
                  Positioned(
                    bottom: 12,
                    left: 12,
                    child: ParticipantNameBadge(
                      name: name,
                      isMicEnabled: widget.participant.isMicrophoneEnabled(),
                      isMuted: widget.isMuted,
                      isScreenshare: _isScreenshare,
                    ),
                  ),
              ],
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
  }

  Future<void> _subscribeToScreenshare(BuildContext context) async {
    final livekitCubit = context.read<LiveKitCubit>();
    await livekitCubit.subscribeToScreenshare(widget.participant.identity);
    if (mounted) {
      setState(() {
        _isSubscribed = true;
      });
    }
  }

  Future<void> _unsubscribeFromScreenshare(BuildContext context) async {
    final livekitCubit = context.read<LiveKitCubit>();
    await livekitCubit.unsubscribeFromScreenshare(widget.participant.identity);
    if (mounted) {
      setState(() {
        _isSubscribed = false;
      });
    }
  }
}
