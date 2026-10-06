import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/screen_share_settings.dart';
import '../../../../../data/classes/server_limits.dart';
import '../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../../logic/cubits/screenshare/screenshare_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/services/host_platform.dart';
import '../../../../common/app_modal.dart';
import '../../../../common/context_menu/context_menu_overlay.dart';
import '../../screenshare/screen_share_settings_dialog.dart';
import '../widgets/control_button.dart';
import 'widgets/screen_share_menu.dart';
import 'widgets/sharing_button.dart';

/// Screen share's place in the call's control bar: a button that starts a
/// share, and while one runs, a button that stops it with a menu beside it
/// for changing the stream without stopping it.
class ScreenShareControl extends StatefulWidget {
  /// Drawn for the user dock: see [ControlButton.dense].
  final bool dense;

  const ScreenShareControl({super.key, this.dense = false});

  @override
  State<ScreenShareControl> createState() => _ScreenShareControlState();
}

class _ScreenShareControlState extends State<ScreenShareControl> {
  final ContextMenuOverlay _menu = ContextMenuOverlay();
  final GlobalKey _buttonKey = GlobalKey();

  @override
  void dispose() {
    _menu.dismiss();
    super.dispose();
  }

  Future<void> _start() async {
    final screenshareCubit = context.read<ScreenshareCubit>();
    final livekitCubit = context.read<LiveKitCubit>();
    final serverCubit = context.read<ServerCubit>();

    // The settings dialog is a *desktop* capture dialog — capture type,
    // window list, bitrate, codec, system-audio toggle. None of it exists
    // where the SDK does the capturing: a browser shows its own picker, and
    // Android shows the MediaProjection consent sheet, which is the picker.
    // Putting ours in front of either would be asking twice, the first time
    // about things that cannot be chosen.
    final ScreenShareSettings settings;
    if (kIsWeb || HostPlatform.isMobile) {
      settings = const ScreenShareSettings();
    } else {
      // The picker is told what this server allows so it can grey out what it
      // will not carry. The clamp in [ScreenshareCubit] still applies — web
      // and mobile never open this dialog at all — but a control that offers
      // a number and then quietly uses a different one is the wrong control.
      final dialogSettings = await showCustomDialog<ScreenShareSettings>(
        context: context,
        build: (_) => ScreenShareSettingsDialog(
          maxShareMbps:
              serverCubit.state.selectedServer?.limits.maxShareMbps ??
              ServerLimits.unlimited,
        ),
      );
      if (dialogSettings == null) return;
      settings = dialogSettings;
    }

    if (!livekitCubit.state.inCall) return;

    await screenshareCubit.startScreenShare(settings: settings);
  }

  /// Opens the menu above the button, its left edge on the button's.
  void _openMenu() {
    final box = _buttonKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final topLeft = box.localToGlobal(Offset.zero);
    _menu.show(
      context,
      ScreenShareMenu(
        onStop: () => context.read<ScreenshareCubit>().stopScreenShare(),
      ),
      topLeft - const Offset(0, _menuGap),
    );
  }

  /// Between the top of the bar's button and the bottom of its menu.
  static const double _menuGap = 8;

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ScreenshareCubit, ScreenshareState>(
      listenWhen: (prev, curr) => prev.isSharing != curr.isSharing,
      // A share that ends with its menu open — the window closed, the
      // call left — takes the menu with it.
      listener: (_, state) {
        if (!state.isSharing) _menu.dismiss();
      },
      buildWhen: (prev, curr) => prev.isSharing != curr.isSharing,
      builder: (context, state) {
        if (!state.isSharing) {
          return ControlButton(
            icon: Icons.present_to_all,
            tooltip: 'Share screen',
            onTap: _start,
            dense: widget.dense,
          );
        }
        final stop = context.read<ScreenshareCubit>().stopScreenShare;
        // Where the SDK captures, there is nothing to change mid-share: the
        // stop button alone.
        if (!ScreenshareCubit.changesQualityLive) {
          return ControlButton(
            icon: Icons.stop_screen_share_outlined,
            isActive: true,
            tooltip: 'Stop sharing',
            onTap: stop,
            dense: widget.dense,
          );
        }
        return SharingButton(
          key: _buttonKey,
          onStop: stop,
          onMenu: _openMenu,
          dense: widget.dense,
        );
      },
    );
  }
}
