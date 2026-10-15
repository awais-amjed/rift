import 'package:flutter/material.dart';

import '../../../../../data/classes/participant_info.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../logic/services/voice_status_icons.dart';
import '../../../../theme/app_motion.dart';
import '../../../../theme/custom_colors.dart';
import '../../../../theme/theme_context.dart';
import '../../channels/channel_list/widgets/voice_channel_tile/widgets/roster_row_metrics.dart';

/// The status icons at the end of a roster row: what somebody is sharing, and
/// whether they can hear or be heard.
///
/// Red is something being *denied* — a microphone off, ears closed. A
/// push-to-talk microphone waiting for its key is grey: nobody has refused
/// anything, they are just not talking. Sharing is
/// the accent instead: it is not a problem, it is the thing you might want to
/// go and look at. A bot that cannot hear is grey: that is how a bot comes,
/// not something anybody did to it, and a red mark on every music bot would
/// drown out the ones that mean something.
class VoiceStatusRowIcons extends StatelessWidget {
  final ParticipantInfo participant;

  /// Whether this listener has muted them for themselves.
  final bool mutedForYou;

  /// A bot with no listening grant for this channel.
  final bool cannotHear;

  const VoiceStatusRowIcons({
    super.key,
    required this.participant,
    required this.mutedForYou,
    this.cannotHear = false,
  });

  /// Shared with the row for a call you are not in, which has no live state
  /// but knows the grant all the same.
  static const cannotHearTooltip =
      'Can’t hear the call. This bot hasn’t been allowed to listen here';

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final size = RosterRowMetrics.of(context).iconSize;
    final icons = voiceStatusIcons(
      participant,
      mutedForYou: mutedForYou,
      cannotHear: cannotHear,
    );

    // Somebody muting is something that happened to the row, not a redraw:
    // the marks pop in and shrink away rather than blinking. Keyed on the
    // whole set, so only a change animates.
    return AnimatedSwitcher(
      duration: AppMotion.state,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: CurvedAnimation(parent: animation, curve: AppMotion.pop),
          child: child,
        ),
      ),
      child: Row(
        key: ValueKey(icons.join(',')),
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          for (final icon in icons)
            Tooltip(
              message: _tooltip(icon),
              child: Icon(
                iconOf(icon),
                size: size,
                color: colorOf(icon, theme),
              ),
            ),
        ],
      ),
    );
  }

  /// The mark for [icon], shared with the member card's words so a state
  /// looks the same in both places.
  static Color colorOf(
    VoiceStatusIcon icon,
    ThemeState theme,
  ) => switch (icon) {
    VoiceStatusIcon.sharingScreen ||
    VoiceStatusIcon.sharingSound => theme.accentBright,
    VoiceStatusIcon.cannotHear ||
    VoiceStatusIcon.waitingToTalk => theme.textTertiary,
    VoiceStatusIcon.mutedForYou => CustomColors.error.withValues(alpha: 0.7),
    VoiceStatusIcon.deafenedByModerator || VoiceStatusIcon.mutedByModerator =>
      CustomColors.error.withValues(alpha: 0.85),
    _ => CustomColors.error,
  };

  static IconData iconOf(VoiceStatusIcon icon) => switch (icon) {
    // The same screen the call controls show while you are sharing one, so
    // the icon means one thing wherever it turns up.
    VoiceStatusIcon.sharingScreen => Icons.monitor_outlined,
    VoiceStatusIcon.sharingSound => Icons.graphic_eq_rounded,
    VoiceStatusIcon.deafened ||
    VoiceStatusIcon.deafenedByModerator ||
    VoiceStatusIcon.cannotHear => Icons.headset_off,
    VoiceStatusIcon.muted ||
    VoiceStatusIcon.mutedByModerator ||
    VoiceStatusIcon.waitingToTalk => Icons.mic_off,
    // Not a crossed microphone: they have not muted themselves, you have
    // turned them off — the same distinction the volume slider makes.
    VoiceStatusIcon.mutedForYou => Icons.volume_off,
  };

  String _tooltip(VoiceStatusIcon icon) => switch (icon) {
    VoiceStatusIcon.sharingScreen => 'Sharing their screen',
    VoiceStatusIcon.sharingSound => 'Sharing sound',
    VoiceStatusIcon.deafened => 'Deafened — they can’t hear the call',
    VoiceStatusIcon.deafenedByModerator => 'Deafened by a moderator',
    VoiceStatusIcon.cannotHear => cannotHearTooltip,
    VoiceStatusIcon.muted => 'Muted',
    VoiceStatusIcon.mutedByModerator => 'Muted by a moderator',
    VoiceStatusIcon.waitingToTalk => 'Push to talk',
    VoiceStatusIcon.mutedForYou => 'Muted for you',
  };
}
