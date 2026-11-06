import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/screen_share_settings.dart';
import '../../../../../data/classes/server_limits.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../../logic/cubits/screenshare/screenshare_cubit.dart';
import '../../../../../logic/services/host_platform.dart';
import '../../../../../logic/services/phone_encoders.dart';
import '../../../../../logic/services/phone_screen.dart';
import '../../../../../logic/services/phone_share_publish.dart';
import '../../../../../logic/services/window_share_portal.dart';
import '../../../../common/app_modal.dart';
import '../../../../common/context_menu/context_menu_overlay.dart';
import '../../screenshare/phone_share_dialog.dart';
import '../../screenshare/screen_share_settings_dialog.dart';
import '../widgets/control_button.dart';
import 'widgets/screen_share_menu.dart';
import 'widgets/sharing_button.dart';
import 'window_sound_step.dart';

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
    final appCubit = context.read<AppCubit>();

    final attempt = screenshareCubit.beginAttempt();
    if (attempt == null) return;

    // The call's server's limit, which is what carries the share; another
    // server may be the one on screen.
    final maxShareMbps =
        livekitCubit.callServer?.limits.maxShareMbps ?? ServerLimits.unlimited;

    // The desktop's dialog also picks what to share. Where the SDK captures,
    // the system asks that: a browser shows its own picker, and Android the
    // MediaProjection consent sheet. A browser's share takes no settings, so
    // it opens no dialog; a phone's dialog asks only how the share goes out.
    ScreenShareSettings settings;
    if (kIsWeb || (HostPlatform.isMobile && !HostPlatform.isAndroid)) {
      settings = const ScreenShareSettings();
    } else {
      final codecs = HostPlatform.isAndroid
          ? await PhoneEncoders.codecs()
          : null;
      final frameRates = HostPlatform.isAndroid
          ? PhoneShare.frameRatesFor(await PhoneScreen.topRefreshRate())
          : const <int>[];
      if (!mounted) return;
      final screen = View.of(context).display.size;
      // Told what this server allows, so it can grey out what it will not
      // carry: a control that offers a number and then quietly uses a
      // different one is the wrong control.
      final dialogSettings = await showCustomDialog<ScreenShareSettings>(
        context: context,
        build: (_) => codecs != null
            ? PhoneShareDialog(
                codecs: codecs,
                shortSide: PhoneShare.shortSideOf(screen),
                frameRates: frameRates,
                maxShareMbps: maxShareMbps,
              )
            : ScreenShareSettingsDialog(maxShareMbps: maxShareMbps),
      );
      if (dialogSettings == null) return;
      settings = dialogSettings;
    }

    String? portalChoice;
    if (WindowSoundStep.appliesTo(settings)) {
      if (!mounted) return;
      final share = await WindowSoundStep.run(context, settings, attempt);
      if (share == null) return;
      (:settings, :portalChoice) = share;
    }

    if (livekitCubit.state.inCall) {
      await screenshareCubit.startScreenShare(
        settings: settings,
        gpuCapture: appCubit.state.gpuScreenCapture,
        portalChoice: portalChoice,
      );
    }
    // Used by the share, the desktop has deleted it already; one the share
    // never reached is deleted here.
    if (portalChoice != null) unawaited(WindowSharePortal.forget(portalChoice));
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
