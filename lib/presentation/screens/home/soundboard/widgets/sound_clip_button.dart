import 'package:flutter/material.dart';

import '../../../../../data/classes/soundboard_sound.dart';
import '../../../../../data/constants.dart';
import '../../../../theme/app_motion.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';

/// One clip, as something to press.
///
/// Deliberately a wide tile rather than an icon: a soundboard is read by name
/// under pressure, and an emoji alone is a rebus. The glyph leads, the name
/// follows, and the name is what is guaranteed to be there.
class SoundClipButton extends StatelessWidget {
  final SoundboardSound sound;

  /// Whether this one was pressed a moment ago. It says the press landed —
  /// there is nothing else to say so, since the clip may be playing out of
  /// four other people's speakers and none of this window's.
  final bool justPressed;

  final VoidCallback? onTap;

  const SoundClipButton({
    super.key,
    required this.sound,
    required this.justPressed,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final radius = BorderRadius.circular(K.radiusRow);
    final enabled = onTap != null;

    return AnimatedContainer(
      duration: AppMotion.react,
      decoration: BoxDecoration(
        color: justPressed ? theme.channelActiveBg : theme.bgTertiary,
        borderRadius: radius,
        border: Border.all(
          color: justPressed ? theme.channelActiveBorder : theme.borderPrimary,
        ),
      ),
      // Inside the fill, or the hover is painted and then covered — the rule
      // `PopoverSurface` documents, which applies again here because this
      // tile paints an opaque background of its own.
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: radius,
          hoverColor: theme.bgHover,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: Text(
                    sound.emoji ?? '♪',
                    style: AppText.row.copyWith(
                      color: sound.emoji == null
                          ? theme.textQuaternary
                          : theme.textPrimary,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    sound.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.row.copyWith(
                      color: enabled ? theme.textPrimary : theme.textQuaternary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
