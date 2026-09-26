import 'package:flutter/material.dart';

import '../../../../../data/classes/participant_info.dart';
import '../../../../../logic/services/voice_status_icons.dart';
import '../../../../theme/custom_colors.dart';
import '../../../../theme/theme_context.dart';
import '../../channels/channel_list/widgets/voice_channel_tile/widgets/roster_row_metrics.dart';

/// The status icons at the end of a roster row: what somebody is sharing, and
/// whether they can hear or be heard.
///
/// Red is something being *denied* — a microphone off, ears closed. Sharing is
/// the accent instead: it is not a problem, it is the thing you might want to
/// go and look at.
class VoiceStatusRowIcons extends StatelessWidget {
  final ParticipantInfo participant;

  /// Whether this listener has muted them for themselves.
  final bool mutedForYou;

  const VoiceStatusRowIcons({
    super.key,
    required this.participant,
    required this.mutedForYou,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final size = RosterRowMetrics.of(context).iconSize;

    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 4,
      children: [
        for (final icon in voiceStatusIcons(
          participant,
          mutedForYou: mutedForYou,
        ))
          Tooltip(
            message: _tooltip(icon),
            child: Icon(
              _icon(icon),
              size: size,
              color: switch (icon) {
                VoiceStatusIcon.sharingScreen ||
                VoiceStatusIcon.sharingSound => theme.accentBright,
                VoiceStatusIcon.mutedForYou => CustomColors.error.withValues(
                  alpha: 0.7,
                ),
                VoiceStatusIcon.deafenedByModerator ||
                VoiceStatusIcon.mutedByModerator =>
                  CustomColors.error.withValues(alpha: 0.85),
                _ => CustomColors.error,
              },
            ),
          ),
      ],
    );
  }

  IconData _icon(VoiceStatusIcon icon) => switch (icon) {
    // The same screen the call controls show while you are sharing one, so
    // the icon means one thing wherever it turns up.
    VoiceStatusIcon.sharingScreen => Icons.monitor_outlined,
    VoiceStatusIcon.sharingSound => Icons.graphic_eq_rounded,
    VoiceStatusIcon.deafened ||
    VoiceStatusIcon.deafenedByModerator => Icons.headset_off,
    VoiceStatusIcon.muted || VoiceStatusIcon.mutedByModerator => Icons.mic_off,
    // Not a crossed microphone: they have not muted themselves, you have
    // turned them off — the same distinction the volume slider makes.
    VoiceStatusIcon.mutedForYou => Icons.volume_off,
  };

  String _tooltip(VoiceStatusIcon icon) => switch (icon) {
    VoiceStatusIcon.sharingScreen => 'Sharing their screen',
    VoiceStatusIcon.sharingSound => 'Sharing sound',
    VoiceStatusIcon.deafened => 'Deafened — they can’t hear the call',
    VoiceStatusIcon.deafenedByModerator => 'Deafened by a moderator',
    VoiceStatusIcon.muted => 'Muted',
    VoiceStatusIcon.mutedByModerator => 'Muted by a moderator',
    VoiceStatusIcon.mutedForYou => 'Muted for you',
  };
}
