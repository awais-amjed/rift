import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/context_menu_region.dart';
import '../../../../theme/custom_colors.dart';
import '../sidebar/widgets/participant_context_menu.dart';

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

  @override
  void initState() {
    super.initState();
    _updateVideoTrack();
    widget.participant.addListener(_onParticipantChanged);
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
    _videoPub = widget.participant.videoTrackPublications
        .where(
          (t) => t.source == TrackSource.camera && t.track != null && !t.muted,
        )
        .cast<TrackPublication?>()
        .firstOrNull;
    _isSpeaking = widget.participant.isSpeaking;
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        final hasVideo = _videoPub != null;
        final isSpeaking = _isSpeaking && !widget.isMuted;
        final name = widget.participant.name;

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
                  _AvatarPlaceholder(
                    name: name,
                    isDark: themeState.isDarkTheme,
                  ),
                // Name + mic badge
                Positioned(
                  bottom: 12,
                  left: 12,
                  child: _NameBadge(
                    name: name,
                    isMicEnabled: widget.participant.isMicrophoneEnabled(),
                    isMuted: widget.isMuted,
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
}

class _AvatarPlaceholder extends StatelessWidget {
  final String name;
  final bool isDark;

  const _AvatarPlaceholder({required this.name, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Center(
          child: Container(
            width: 112,
            height: 112,
            decoration: BoxDecoration(
              color: isDark
                  ? CustomColors.bgTertiaryDark
                  : CustomColors.bgActiveLight,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: themeState.borderPrimary),
            ),
            alignment: Alignment.center,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.w700,
                color: themeState.textTertiary,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NameBadge extends StatelessWidget {
  final String name;
  final bool isMicEnabled;
  final bool isMuted;

  const _NameBadge({
    required this.name,
    required this.isMicEnabled,
    required this.isMuted,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color:
                (themeState.isDarkTheme
                        ? CustomColors.bgTertiaryDark
                        : CustomColors.bgSecondaryLight)
                    .withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: themeState.borderPrimary),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: themeState.textPrimary,
                ),
              ),
              if (!isMicEnabled || isMuted) ...[
                const SizedBox(width: 6),
                Icon(Icons.mic_off, size: 13, color: CustomColors.error),
              ],
            ],
          ),
        );
      },
    );
  }
}
