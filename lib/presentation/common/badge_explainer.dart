import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../logic/cubits/theme/theme_cubit.dart';
import '../theme/app_text.dart';
import 'popover_surface.dart';

/// Opens a small popover explaining what a badge means, anchored to it.
///
/// The app is full of three- and seven-letter chips — `MOD`, `WEBHOOK` — that
/// are obvious to whoever added them and opaque to everybody else. A tooltip
/// half-answers it: it needs a mouse, so a phone never sees one, and it needs
/// you to already suspect there is something to find.
///
/// So a badge that carries a real consequence is **tappable**, and says in a
/// sentence what it means for the thing it is attached to. If a badge does not
/// deserve a sentence, it probably should not be on screen.
Future<void> showBadgeExplainer(
  BuildContext anchorContext, {
  required IconData icon,
  required Color iconColor,
  required String title,
  required String body,
}) async {
  final box = anchorContext.findRenderObject() as RenderBox?;
  final overlay =
      Overlay.of(anchorContext).context.findRenderObject() as RenderBox?;
  if (box == null || overlay == null) return;

  final anchor = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
  // The menu builds under the navigator, outside the app's provider scope.
  final themeCubit = anchorContext.read<ThemeCubit>();
  final themeState = themeCubit.state;

  await showMenu<void>(
    context: anchorContext,
    position: RelativeRect.fromRect(anchor, Offset.zero & overlay.size),
    // Chrome comes from [PopoverSurface]; Material must not paint its own fill
    // or elevation tint behind it.
    color: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    shadowColor: Colors.transparent,
    elevation: 0,
    constraints: const BoxConstraints(minWidth: 240, maxWidth: 280),
    items: [
      PopupMenuItem<void>(
        // Nothing in here is a choice, so tapping the text should not feel
        // like picking something. Dismiss by tapping outside or pressing Esc.
        enabled: false,
        padding: EdgeInsets.zero,
        child: BlocProvider.value(
          value: themeCubit,
          child: PopoverSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              spacing: 6,
              children: [
                Row(
                  spacing: 6,
                  children: [
                    Icon(icon, size: 14, color: iconColor),
                    Flexible(
                      child: Text(
                        title,
                        style: AppText.row.copyWith(
                          fontWeight: FontWeight.w700,
                          color: themeState.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  body,
                  style: AppText.meta.copyWith(
                    color: themeState.textSecondary,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}
