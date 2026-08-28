import 'package:flutter/material.dart';

import '../../../../../../data/classes/server_member.dart';
import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../common/app_switch.dart';
import '../../../../../theme/app_text.dart';
import '../../../../../theme/custom_colors.dart';

/// One bot, and whether it holds this channel's key.
///
/// The line under the name is the bot's own `data_use` declaration where it has
/// published one (BOTS.md §8). It is an advertisement, not evidence — nothing
/// is authorised by what a bot claims — but for a bot that forwards anywhere it
/// is the sentence that matters most, and this is the moment it matters.
class ChannelBotRow extends StatelessWidget {
  final ThemeState themeState;
  final ServerMember bot;
  final bool granted;
  final bool busy;
  final VoidCallback? onChanged;

  const ChannelBotRow({
    super.key,
    required this.themeState,
    required this.bot,
    required this.granted,
    required this.busy,
    this.onChanged,
  });

  String? get _note {
    final declared = bot.manifest.dataUse;
    if (declared != null && declared.trim().isNotEmpty) return declared;
    return granted
        ? 'Reads every message sent here.'
        : 'Only sees what it is sent.';
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: busy ? 0.5 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              granted ? Icons.hearing_rounded : Icons.smart_toy_outlined,
              size: 17,
              // Amber while it is listening, matching the header chip and the
              // unencrypted badge: the same fact wearing a different hat.
              color: granted ? CustomColors.warning : themeState.textTertiary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bot.displayName,
                    style: AppText.row.copyWith(color: themeState.textPrimary),
                  ),
                  if (_note case final note?) ...[
                    const SizedBox(height: 3),
                    Text(
                      note,
                      style: AppText.secondary.copyWith(
                        color: themeState.textTertiary,
                        fontSize: 11.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            AppSwitch(
              value: granted,
              onChanged: onChanged == null ? null : (_) => onChanged!(),
            ),
          ],
        ),
      ),
    );
  }
}
