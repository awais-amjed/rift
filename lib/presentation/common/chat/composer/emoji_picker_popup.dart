import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';

import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../emoji_text.dart';
import '../../popover_surface.dart';

const double _popupWidth = 340;
const double _popupHeight = 320;

/// Show the full emoji picker as a popover anchored to [anchorContext] (the
/// composer's emoji button), matching the quick-reaction picker rather than
/// dropping a keyboard-sized panel into the layout.
///
/// Picked emoji go straight into [controller] at the cursor, and the popover
/// stays open so several can be inserted in a row — it closes on an outside
/// tap or Escape. [onEmojiSelected] fires after each insert so the composer
/// can re-evaluate its send button.
Future<void> showEmojiPickerPopup(
  BuildContext anchorContext, {
  required ThemeState themeState,
  required TextEditingController controller,
  required VoidCallback onEmojiSelected,
}) async {
  final box = anchorContext.findRenderObject() as RenderBox?;
  final overlay =
      Overlay.of(anchorContext).context.findRenderObject() as RenderBox?;
  if (box == null || overlay == null) return;

  final anchor = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;

  await showMenu<void>(
    context: anchorContext,
    position: RelativeRect.fromRect(anchor, Offset.zero & overlay.size),
    // Chrome comes from [PopoverSurface] below, so this looks like the app's
    // other popovers rather than a Material menu. Material must not paint its
    // own fill or elevation tint behind it.
    color: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    shadowColor: Colors.transparent,
    elevation: 0,
    constraints: const BoxConstraints(
      minWidth: _popupWidth,
      maxWidth: _popupWidth,
    ),
    items: [
      PopupMenuItem<void>(
        // Disabled so tapping an emoji doesn't dismiss the whole menu; the
        // picker's own gesture handlers still receive the tap.
        enabled: false,
        padding: EdgeInsets.zero,
        child: PopoverSurface(
          child: SizedBox(
            width: _popupWidth,
            height: _popupHeight,
            child: _picker(themeState, controller, onEmojiSelected),
          ),
        ),
      ),
    ],
  );
}

Widget _picker(
  ThemeState themeState,
  TextEditingController controller,
  VoidCallback onEmojiSelected,
) {
  return ClipRRect(
    // One inside the surface's radius, so the picker's own background stops
    // short of the ring instead of painting over its corners.
    borderRadius: BorderRadius.circular(PopoverSurface.radius - 1),
    child: EmojiPicker(
      textEditingController: controller,
      onEmojiSelected: (_, _) => onEmojiSelected(),
      config: Config(
        height: _popupHeight,
        // Without this the picker's own grid shows the same monochrome
        // glyphs the message list used to.
        emojiTextStyle: emojiRunStyle,
        emojiViewConfig: EmojiViewConfig(
          backgroundColor: themeState.bgElevated,
          columns: 8,
          emojiSizeMax: 24,
        ),
        categoryViewConfig: CategoryViewConfig(
          backgroundColor: themeState.bgElevated,
          iconColor: themeState.textQuaternary,
          iconColorSelected: themeState.primary,
          indicatorColor: themeState.primary,
          dividerColor: themeState.borderPrimary,
          backspaceColor: themeState.primary,
        ),
        bottomActionBarConfig: const BottomActionBarConfig(enabled: false),
        searchViewConfig: SearchViewConfig(
          backgroundColor: themeState.bgElevated,
          buttonIconColor: themeState.textTertiary,
        ),
      ),
    ),
  );
}
