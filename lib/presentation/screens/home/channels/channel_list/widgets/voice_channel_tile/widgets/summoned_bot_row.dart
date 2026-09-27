import 'package:flutter/material.dart';

import '../../../../../../../common/context_menu/context_menu_panel.dart';
import '../../../../../../../common/context_menu_region.dart';
import '../../../../../../../common/squircle_avatar.dart';
import '../../../../../../../theme/app_text.dart';
import '../../../../../../../theme/theme_context.dart';
import '../../../../../sidebar/widgets/participant_bot_section.dart';
import 'roster_row_metrics.dart';

/// A bot that was called into this call but is not in it.
///
/// The rest of the roster is drawn from who is *connected*; this is drawn from
/// the summon, which is why it is a separate row rather than another
/// participant. A bot that is down, or slow, or has crashed mid-track leaves
/// one behind — and "Send away" lives on the participant menu, which needs the
/// bot to be in the call, so without this the summon could be neither seen nor
/// cleared. A summon expires after an hour (`app.expire_bot_voice_summons`); this is what makes
/// the hour visible rather than something to wait out.
///
/// Dimmed, and with no volume or mute: there is nothing to hear yet. It says
/// what it is rather than pretending to be a participant.
class SummonedBotRow extends StatelessWidget {
  final String botId;
  final String name;
  final String channelId;
  const SummonedBotRow({
    super.key,
    required this.botId,
    required this.name,
    required this.channelId,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return ContextMenuRegion(
      contextMenu: ContextMenuPanel(
        heading: 'Summoned',
        subheading: name,
        leading: SquircleAvatar(name: name, seed: botId, size: 24),
        children: [
          ParticipantBotSection(
            targetUserId: botId,
            voiceChannelId: channelId,
            name: name,
          ),
        ],
      ),
      child: Opacity(
        opacity: 0.55,
        child: Padding(
          padding: RosterRowMetrics.of(context).padding,
          child: Row(
            spacing: 8,
            children: [
              SquircleAvatar(
                name: name,
                seed: botId,
                size: RosterRowMetrics.of(context).avatarSize,
              ),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: RosterRowMetrics.of(
                    context,
                  ).nameStyle.copyWith(color: themeState.textSecondary),
                ),
              ),
              Text(
                'summoned',
                style: AppText.meta.copyWith(color: themeState.textTertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
