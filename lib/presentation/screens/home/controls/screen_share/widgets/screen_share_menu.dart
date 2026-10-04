import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/classes/screen_share_settings.dart';
import '../../../../../../data/constants.dart';
import '../../../../../../logic/cubits/screenshare/screenshare_cubit.dart';
import '../../../../../common/context_menu/context_menu_item.dart';
import '../../../../../common/context_menu/context_menu_panel.dart';
import '../../../../../common/context_menu/context_menu_submenu_item.dart';
import '../../../../../common/context_menu_region.dart';
import '../../../../../theme/theme_context.dart';
import 'change_stream_quality.dart';
import 'stream_quality_menu.dart';

/// What the chevron beside a running share opens: stop it, or change it
/// without stopping it. Toggles leave the menu open, the way the call's other
/// menus do, so the tick can be seen to move.
class ScreenShareMenu extends StatelessWidget {
  final VoidCallback onStop;

  const ScreenShareMenu({super.key, required this.onStop});

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return BlocBuilder<ScreenshareCubit, ScreenshareState>(
      buildWhen: (prev, curr) => prev.settings != curr.settings,
      builder: (context, state) {
        final settings = state.settings ?? const ScreenShareSettings();
        return ContextMenuPanel(
          children: [
            // First, as the menu opens upward: the row furthest from the
            // pointer is the one that ends the share.
            ContextMenuItem(
              icon: Icons.stop_screen_share_outlined,
              label: 'Stop sharing',
              isDangerous: true,
              onTap: () {
                ContextMenuScope.of(context)?.call();
                onStop();
              },
            ),
            Divider(height: 9, color: themeState.borderPrimary),
            ContextMenuSubmenuItem(
              icon: Icons.tune_rounded,
              label: 'Stream quality',
              submenuBuilder: (_) => const StreamQualityMenu(),
            ),
            if (canToggleStreamSound(settings))
              ContextMenuItem(
                icon: settings.shareAudio
                    ? Icons.volume_up_outlined
                    : Icons.volume_off_outlined,
                label: 'Share stream audio',
                trailing: settings.shareAudio
                    ? const Icon(Icons.check_rounded, size: K.iconRow)
                    : null,
                onTap: () => changeStreamQuality(
                  context,
                  shareAudio: !settings.shareAudio,
                ),
              ),
          ],
        );
      },
    );
  }
}
