import 'package:flutter/material.dart';

import '../../../../../data/classes/bot_manifest.dart';
import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';

/// A listed bot's published commands and its data-use sentence.
///
/// **This is the one place the sentence is read before it binds anything.**
/// A running bot's manifest is shown beside its commands in the composer, by
/// which point the bot is already on the server and holds whatever it was
/// given. Here it is still a decision — so `data_use` is not tucked under the
/// commands but set above them, where somebody choosing what to install reads
/// it first.
///
/// Advertisement, like the manifest it mirrors: nothing here authorises
/// anything, and the author writes both halves.
class BotCommandList extends StatelessWidget {
  final BotManifest manifest;

  /// How many commands to show before saying how many are left. A listing row
  /// is a paragraph, not a manual.
  final int limit;

  const BotCommandList({super.key, required this.manifest, this.limit = 4});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final commands = manifest.commands;
    final dataUse = manifest.dataUse;
    if (commands.isEmpty && (dataUse == null || dataUse.isEmpty)) {
      return const SizedBox.shrink();
    }

    final shown = commands.take(limit).toList();
    final hidden = commands.length - shown.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dataUse != null && dataUse.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 6,
            children: [
              Icon(
                Icons.privacy_tip_outlined,
                size: 14,
                color: theme.textTertiary,
              ),
              Expanded(
                child: Text(
                  dataUse,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.label.copyWith(
                    fontWeight: FontWeight.w400,
                    color: theme.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (shown.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              for (final command in shown) _chip(theme, command),
              if (hidden > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text(
                    '+$hidden more',
                    style: AppText.label.copyWith(color: theme.textTertiary),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  /// `/roll <dice>` — mono, because it is a string to be typed exactly.
  Widget _chip(ThemeState theme, BotCommandSpec command) {
    final usage = command.usage;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: theme.bgTertiary,
        borderRadius: BorderRadius.circular(K.radiusRow),
      ),
      child: Text(
        usage == null || usage.isEmpty
            ? '/${command.name}'
            : '/${command.name} $usage',
        style: AppText.code.copyWith(color: theme.textSecondary),
      ),
    );
  }
}
