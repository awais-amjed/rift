import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../../data/classes/screen_share_settings.dart';
import '../../../../../../data/constants.dart';
import '../../../../../../logic/cubits/screenshare/screenshare_cubit.dart';
import '../../../../../../logic/services/gpu_codecs.dart';
import '../../../../../../logic/services/host_platform.dart';
import '../../../../../common/context_menu/context_menu_item.dart';
import '../../../../../common/context_menu/context_menu_panel.dart';
import '../../../../../common/context_menu/context_menu_scope.dart';
import '../../../../../common/context_menu/context_menu_submenu_item.dart';
import '../../../../../theme/theme_context.dart';
import 'change_stream_quality.dart';
import 'stream_choice_menu.dart';

/// What the chevron beside a running share opens: stop it, or change it
/// without stopping it — its resolution, frame rate and codec each a submenu
/// of their own, showing what it is on now. Toggles leave the menu open, the
/// way the call's other menus do, so the tick can be seen to move.
class ScreenShareMenu extends StatelessWidget {
  final VoidCallback onStop;

  const ScreenShareMenu({super.key, required this.onStop});

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return BlocBuilder<ScreenshareCubit, ScreenshareState>(
      buildWhen: (prev, curr) =>
          prev.settings != curr.settings || prev.codec != curr.codec,
      builder: (context, state) {
        final settings = state.settings ?? const ScreenShareSettings();
        final codec = state.codec ?? settings.videoCodec;
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
              icon: Icons.aspect_ratio_rounded,
              label: 'Resolution',
              value: settings.resolutionLabel,
              submenuBuilder: (_) => StreamChoiceMenu(
                heading: 'Resolution',
                choices: (state) => [
                  for (final height in ScreenShareSettings.resolutions)
                    (
                      label: ScreenShareSettings.labelFor(height),
                      chosen: state.settings?.resolution == height,
                      onTap: () =>
                          changeStreamQuality(context, resolution: height),
                    ),
                ],
              ),
            ),
            ContextMenuSubmenuItem(
              icon: Icons.speed_rounded,
              label: 'Frame rate',
              value: '${settings.fps} fps',
              submenuBuilder: (_) => StreamChoiceMenu(
                heading: 'Frame rate',
                choices: (state) => [
                  for (final fps in ScreenShareSettings.frameRatesAt(
                    (state.settings ?? settings).resolution,
                  ))
                    (
                      label: '$fps fps',
                      chosen: state.settings?.fps == fps,
                      onTap: () => changeStreamQuality(context, fps: fps),
                    ),
                ],
              ),
            ),
            ContextMenuSubmenuItem(
              icon: Icons.video_settings_rounded,
              label: 'Codec',
              value: ScreenShareSettings.nameOf(codec),
              submenuBuilder: (_) => StreamChoiceMenu(
                heading: 'Codec',
                choices: (state) => [
                  for (final offered in ScreenShareSettings.codecsOffered(
                    gpuOnlyH264: HostPlatform.encodesH264OnGpuOnly,
                    gpu: GpuCodecs.known,
                  ))
                    (
                      label: ScreenShareSettings.nameOf(offered),
                      chosen: (state.codec ?? codec) == offered,
                      onTap: () => changeStreamQuality(context, codec: offered),
                    ),
                ],
              ),
            ),
            // Never without something to turn on: a Linux share with no app
            // picked takes every app's sound but Rift's.
            if (HostPlatform.capturesSystemAudio)
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
