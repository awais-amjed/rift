import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:toastification/toastification.dart';

import '../../../../../data/classes/screen_share_settings.dart';
import '../../../../../data/classes/server_limits.dart';
import '../../../../../data/enums/server_permission.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../../logic/cubits/screenshare/screenshare_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/helper_methods.dart';
import '../../../../../logic/services/host_platform.dart';
import '../../../../../logic/services/phone_encoders.dart';
import '../../../../../logic/services/phone_screen.dart';
import '../../../../../logic/services/phone_share_publish.dart';
import '../../../../../logic/services/web_share_publish.dart';
import '../../../../../logic/services/window_share_portal.dart';
import '../../../../common/app_modal.dart';
import '../../../../common/context_menu/context_menu_overlay.dart';
import '../../screenshare/screen_share_settings_dialog.dart';
import '../../screenshare/sdk_share_dialog.dart';
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
    // MediaProjection consent sheet; their dialog asks only how the share
    // goes out. An iPhone's share takes no settings, so it opens no dialog.
    ScreenShareSettings settings;
    if (HostPlatform.isMobile && !HostPlatform.isAndroid) {
      settings = const ScreenShareSettings();
    } else {
      final sdk = kIsWeb || HostPlatform.isAndroid;
      final codecs = sdk ? await PhoneEncoders.codecs() : null;
      final hardwareH264 = kIsWeb && await WebShare.hardwareH264();
      final frameRates = kIsWeb
          ? WebShare.frameRates
          : HostPlatform.isAndroid
          ? PhoneShare.frameRatesFor(await PhoneScreen.topRefreshRate())
          : const <int>[];
      if (!mounted) return;
      // Read only on a phone, the one dialog that uses it. On Linux a view
      // can name a display the engine no longer lists once a monitor sleeps
      // and wakes, and `display` then throws: the Share button did nothing
      // until Rift restarted (report 5de4bfed).
      final shortSide = HostPlatform.isAndroid
          ? PhoneShare.shortSideOf(View.of(context).display.size)
          : 0;
      // Told what this server allows, so it can grey out what it will not
      // carry: a control that offers a number and then quietly uses a
      // different one is the wrong control.
      final dialogSettings = await showCustomDialog<ScreenShareSettings>(
        context: context,
        build: (_) => switch (codecs) {
          null => ScreenShareSettingsDialog(maxShareMbps: maxShareMbps),
          _ when kIsWeb => SdkShareDialog(
            codecs: WebShare.codecsOffered(codecs, hardwareH264: hardwareH264),
            autoCodec: WebShare.autoCodec(codecs, hardwareH264: hardwareH264),
            resolutions: WebShare.resolutions,
            frameRates: frameRates,
            opening: WebShare.opening,
            offersSound: true,
            maxShareMbps: maxShareMbps,
          ),
          _ => SdkShareDialog(
            codecs: codecs,
            autoCodec: PhoneShare.autoCodec(codecs),
            resolutions: PhoneShare.resolutionsFor(shortSide),
            frameRates: frameRates,
            opening: (saved) => PhoneShare.opening(
              saved,
              shortSide: shortSide,
              frameRates: frameRates,
            ),
            maxShareMbps: maxShareMbps,
          ),
        },
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
          // The call's channel can take sharing from a role
          // (`channel_overrides`), and the token would be refused there.
          final call = context.select<LiveKitCubit, (String?, String?)>(
            (c) => (c.state.currentServerId, c.state.currentChannelId),
          );
          final mayShare = context.select<ServerCubit, bool>(
            (c) =>
                c.state
                    .permissionsIn(call.$1, call.$2)
                    ?.can(ServerPermission.screenShare) ??
                true,
          );
          return ControlButton(
            icon: Icons.present_to_all,
            tooltip: mayShare ? 'Share screen' : 'You can\'t share here',
            onTap: mayShare
                ? _start
                : () => HelperMethods.showToast(
                    title: 'Sharing is off here',
                    description:
                        'This channel doesn\'t let you share your screen.',
                    type: ToastificationType.info,
                  ),
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
