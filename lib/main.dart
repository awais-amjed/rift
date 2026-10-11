import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:go_router/go_router.dart';
import 'package:keyboard_dismisser/keyboard_dismisser.dart';
import 'package:sizer/sizer.dart';
import 'package:toastification/toastification.dart';
import 'package:window_manager/window_manager.dart';

import 'app_bootstrap.dart';
import 'data/constants.dart';
import 'data/repositories/session_repository.dart';
import 'logic/cubits/app/app_cubit.dart';
import 'logic/cubits/theme/theme_cubit.dart';
import 'logic/cubits/vault/vault_cubit.dart';
import 'logic/helper_methods.dart';
import 'logic/ptt/push_to_talk_listener.dart';
import 'logic/services/host_platform.dart';
import 'logic/services/login_launch/login_launch.dart';
import 'logic/services/storage_namespace.dart';
import 'logic/services/window_focus_service.dart';
import 'logic/services/window_fullscreen.dart';
import 'logic/shortcuts/call_shortcut_listener.dart';
import 'presentation/app_providers.dart';
import 'presentation/common/app_toast.dart';
import 'presentation/common/ducking/ducking_hint_listener.dart';
import 'presentation/common/notices/notice_listeners.dart';
import 'presentation/common/title_bar_overlay.dart';
import 'presentation/routing/app_routes.dart';
import 'presentation/screens/home/calls/incoming_call_overlay.dart';
import 'presentation/screens/pip/pip_overlay.dart';
import 'presentation/theme/app_theme.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  StorageNamespace.readArguments(args);
  LoginLaunch.readArguments(args);
  final appCubit = await AppBootstrap.run();
  // One for the app: the vault signs in through it when joining, and every
  // server call after that does.
  final session = SessionRepository();
  runApp(
    MyApp(
      appCubit: appCubit,
      vaultCubit: VaultCubit(session: session),
      session: session,
    ),
  );
}

/// The app shell: window listeners, the router, and the theme.
/// The cubits it provides are in [AppProviders].
class MyApp extends StatefulWidget {
  final AppCubit appCubit;
  final VaultCubit vaultCubit;
  final SessionRepository session;

  const MyApp({
    super.key,
    required this.appCubit,
    required this.vaultCubit,
    required this.session,
  });

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp>
    with WindowListener, WidgetsBindingObserver {
  late final GoRouter _router = AppRoutes.router(widget.vaultCubit);

  @override
  void initState() {
    super.initState();
    // See AppBootstrap.run: these two plugins exist on desktop only.
    if (HostPlatform.drawsOwnWindowChrome) {
      windowManager.addListener(this);
    }
    // A phone has no window to lose focus, so the same question — is the user
    // looking at this? — is answered by the app lifecycle instead. Without
    // this the focus service stays true forever there and a notification is
    // never worth showing.
    WidgetsBinding.instance.addObserver(this);
    HelperMethods.initEasyLoading();
    widget.vaultCubit.checkVaultStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (HostPlatform.drawsOwnWindowChrome) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  // Focus tracking drives whether incoming messages raise an OS notification —
  // we only notify while the user isn't looking at the app.
  /// Resumed is the only state that means "on screen and interactive";
  /// inactive covers a half-swiped app switcher and a notification shade, and
  /// paused and hidden are plainly away. Desktop keeps using the window
  /// events, which are more precise than the lifecycle is there.
  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (HostPlatform.drawsOwnWindowChrome) return;
    WindowFocusService.instance.setFocused(
      lifecycle == AppLifecycleState.resumed,
    );
  }

  @override
  void onWindowFocus() => WindowFocusService.instance.setFocused(true);

  @override
  void onWindowBlur() => WindowFocusService.instance.setFocused(false);

  @override
  void onWindowMinimize() => WindowFocusService.instance.setFocused(false);

  @override
  void onWindowRestore() => WindowFocusService.instance.setFocused(true);

  @override
  void onWindowResize() async {
    if (WindowFullscreen.isOn) return;
    final size = await windowManager.getSize();
    widget.appCubit.saveWindowSize(size);
  }

  @override
  void onWindowMove() async {
    if (WindowFullscreen.isOn) return;
    final position = await windowManager.getPosition();
    widget.appCubit.saveWindowPosition(position);
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardDismisser(
      child: AppProviders(
        appCubit: widget.appCubit,
        vaultCubit: widget.vaultCubit,
        session: widget.session,
        child: Sizer(
          builder: (context, orientation, screenType) {
            // Watched, not `context.theme`: this is what builds the theme,
            // so there is no Theme above it yet to read one from.
            final themeState = context.watch<ThemeCubit>().state;
            return PushToTalkListener(
              child: CallShortcutListener(
                child: MaterialApp.router(
                  routerConfig: _router,
                  darkTheme: AppTheme.dark(themeState.palette),
                  theme: AppTheme.light(themeState.palette),
                  themeMode: themeState.themeMode,
                  // Inside the app, not around it: a toast is drawn by
                  // `AppToast`, which reads the palette off the `ThemeData`
                  // this `MaterialApp` installs — around it there is no theme
                  // to read and every toast fell back to the package's own.
                  builder: EasyLoading.init(
                    builder: (context, child) => ToastificationWrapper(
                      // Clear of the title bar: a toast arrives in the same
                      // corner the window buttons live in.
                      config: const ToastificationConfig(
                        alignment: Alignment.topRight,
                        itemWidth: AppToast.maxWidth,
                        marginBuilder: _toastMargin,
                      ),
                      // Around the navigator, so a ringing call is above
                      // every page, dialog and sheet — see IncomingCallOverlay.
                      child: NoticeListeners(
                        child: DuckingHintListener(
                          child: PipOverlay(
                            child: TitleBarOverlay(
                              child: IncomingCallOverlay(child: child!),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Where a toast sits: below the title bar, in from the window's edge.
EdgeInsetsGeometry _toastMargin(BuildContext context, AlignmentGeometry _) =>
    const EdgeInsets.only(top: K.titleBarHeight + 12, right: 16, left: 16);
