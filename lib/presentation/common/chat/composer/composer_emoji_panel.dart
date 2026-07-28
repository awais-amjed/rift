import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';

import '../../../../logic/cubits/theme/theme_cubit.dart';

/// The emoji keyboard that drops below the composer bar. It inserts straight
/// into the field's controller, so a picked emoji lands at the cursor.
class ComposerEmojiPanel extends StatelessWidget {
  static const double _height = 256;

  final TextEditingController controller;
  final ThemeState themeState;

  /// Fires after an insert so the composer can re-evaluate its send button.
  final VoidCallback onEmojiSelected;

  const ComposerEmojiPanel({
    super.key,
    required this.controller,
    required this.themeState,
    required this.onEmojiSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: SizedBox(
        height: _height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: EmojiPicker(
            textEditingController: controller,
            onEmojiSelected: (_, _) => onEmojiSelected(),
            config: Config(
              height: _height,
              emojiViewConfig: EmojiViewConfig(
                backgroundColor: themeState.bgSecondary,
                columns: 9,
                emojiSizeMax: 26,
              ),
              categoryViewConfig: CategoryViewConfig(
                backgroundColor: themeState.bgSecondary,
                iconColor: themeState.textQuaternary,
                iconColorSelected: themeState.primary,
                indicatorColor: themeState.primary,
                dividerColor: themeState.borderPrimary,
                backspaceColor: themeState.primary,
              ),
              bottomActionBarConfig: const BottomActionBarConfig(
                enabled: false,
              ),
              searchViewConfig: SearchViewConfig(
                backgroundColor: themeState.bgSecondary,
                buttonIconColor: themeState.textTertiary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
