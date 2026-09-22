import 'package:flutter/material.dart';

import '../../../../../../data/classes/channel.dart';
import '../../../../../../data/constants.dart';
import '../../../../../../data/enums/channel_type.dart';
import '../../../../../theme/app_text.dart';
import '../../../../../theme/theme_context.dart';

/// One channel in the quick switcher's results.
///
/// The highlight follows the keyboard, not the pointer, so it is drawn as a
/// filled row rather than a hover state — otherwise arrowing down and moving
/// the mouse would light two rows at once.
class QuickSwitcherRow extends StatelessWidget {
  final Channel channel;
  final bool isHighlighted;
  final VoidCallback onTap;

  const QuickSwitcherRow({
    super.key,
    required this.channel,
    required this.isHighlighted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    final isVoice = channel.channelType == ChannelType.voice;

    return Material(
      color: isHighlighted ? themeState.channelActiveBg : Colors.transparent,
      borderRadius: BorderRadius.circular(K.radiusRow),
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        borderRadius: BorderRadius.circular(K.radiusRow),
        hoverColor: themeState.bgHover,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            spacing: 10,
            children: [
              Icon(
                isVoice ? Icons.volume_up_rounded : Icons.tag_rounded,
                size: 16,
                color: isHighlighted
                    ? themeState.accentBright
                    : themeState.textQuaternary,
              ),
              Expanded(
                child: Text(
                  channel.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.row.copyWith(
                    color: isHighlighted
                        ? themeState.channelActiveText
                        : themeState.textSecondary,
                  ),
                ),
              ),
              Text(
                isVoice ? 'Voice' : 'Text',
                style: AppText.meta.copyWith(color: themeState.textTertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
