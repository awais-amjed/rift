import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../popover_surface.dart';
import 'emoji_picker_panel.dart';

/// Show the emoji picker as a popover anchored to [anchorContext] (the
/// composer's emoji button), matching the quick-reaction picker rather than
/// dropping a keyboard-sized panel into the layout.
///
/// Picked emoji go straight into [controller] at the cursor, and the popover
/// stays open so several can be inserted in a row — it closes on an outside
/// tap or Escape. [onEmojiSelected] fires after each insert so the composer
/// can re-evaluate its send button.
Future<void> showEmojiPickerPopup(
  BuildContext anchorContext, {
  required TextEditingController controller,
  required VoidCallback onEmojiSelected,
}) async {
  final box = anchorContext.findRenderObject() as RenderBox?;
  final overlay =
      Overlay.of(anchorContext).context.findRenderObject() as RenderBox?;
  if (box == null || overlay == null) return;

  final anchor = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
  // The menu builds under the navigator, outside the app's provider scope.
  final appCubit = anchorContext.read<AppCubit>();
  final themeCubit = anchorContext.read<ThemeCubit>();

  await showMenu<void>(
    context: anchorContext,
    position: RelativeRect.fromRect(anchor, Offset.zero & overlay.size),
    // Chrome comes from [PopoverSurface], so this looks like the app's other
    // popovers rather than a Material menu. Material must not paint its own
    // fill or elevation tint behind it.
    color: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    shadowColor: Colors.transparent,
    elevation: 0,
    constraints: const BoxConstraints(
      minWidth: EmojiPickerPanel.width,
      maxWidth: EmojiPickerPanel.width,
    ),
    items: [
      PopupMenuItem<void>(
        // Disabled so tapping an emoji doesn't dismiss the whole menu; the
        // panel's own gesture handlers still receive the tap.
        enabled: false,
        padding: EdgeInsets.zero,
        child: MultiBlocProvider(
          providers: [
            BlocProvider.value(value: appCubit),
            BlocProvider.value(value: themeCubit),
          ],
          child: PopoverSurface(
            child: ClipRRect(
              // One inside the surface's radius, so the panel's rows stop
              // short of the ring instead of painting over its corners.
              borderRadius: BorderRadius.circular(PopoverSurface.radius - 1),
              child: EmojiPickerPanel(
                onSelected: (emoji) {
                  _insert(controller, emoji);
                  onEmojiSelected();
                },
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

/// Drops [emoji] in at the cursor, replacing any selection, and leaves the
/// caret after it — so typing carries on where you'd expect.
void _insert(TextEditingController controller, String emoji) {
  final value = controller.value;
  final selection = value.selection;
  if (!selection.isValid) {
    controller.text = value.text + emoji;
    return;
  }
  final text = value.text.replaceRange(selection.start, selection.end, emoji);
  controller.value = value.copyWith(
    text: text,
    selection: TextSelection.collapsed(offset: selection.start + emoji.length),
    composing: TextRange.empty,
  );
}
