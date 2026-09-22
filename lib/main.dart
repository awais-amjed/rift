import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:go_router/go_router.dart';
import 'package:keyboard_dismisser/keyboard_dismisser.dart';
import 'package:sizer/sizer.dart';
import 'package:toastification/toastification.dart';
import 'package:window_manager/window_manager.dart';

import 'app_bootstrap.dart';
import 'logic/cubits/app/app_cubit.dart';
import 'logic/cubits/theme/theme_cubit.dart';
import 'logic/cubits/vault/vault_cubit.dart';
import 'logic/helper_methods.dart';
import 'logic/ptt/push_to_talk_listener.dart';
import 'logic/services/host_platform.dart';
import 'logic/services/window_focus_service.dart';
import 'presentation/app_providers.dart';
import 'presentation/common/title_bar_overlay.dart';
import 'presentation/routing/app_routes.dart';
import 'presentation/screens/pip/pip_overlay.dart';
import 'presentation/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final appCubit = await AppBootstrap.run();
  runApp(MyApp(appCubit: appCubit, vaultCubit: VaultCubit()));
}

/// The app shell: window listeners, the router, and the theme.
/// The cubits it provides are in [AppProviders].
class MyApp extends StatefulWidget {
  final AppCubit appCubit;
  final VaultCubit vaultCubit;

  const MyApp({super.key, required this.appCubit, required this.vaultCubit});

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
    final size = await windowManager.getSize();
    widget.appCubit.saveWindowSize(size);
  }

  @override
  void onWindowMove() async {
    final position = await windowManager.getPosition();
    widget.appCubit.saveWindowPosition(position);
  }

  @override
  Widget build(BuildContext context) {
    return ToastificationWrapper(
      child: KeyboardDismisser(
        child: AppProviders(
          appCubit: widget.appCubit,
          vaultCubit: widget.vaultCubit,
          child: Sizer(
            builder: (context, orientation, screenType) {
              // Watched, not `context.theme`: this is what builds the theme,
              // so there is no Theme above it yet to read one from.
              final themeState = context.watch<ThemeCubit>().state;
              return PushToTalkListener(
                child: MaterialApp.router(
                  routerConfig: _router,
                  darkTheme: AppTheme.dark(themeState.palette),
                  theme: AppTheme.light(themeState.palette),
                  themeMode: themeState.themeMode,
                  builder: EasyLoading.init(
                    builder: (context, child) =>
                        PipOverlay(child: TitleBarOverlay(child: child!)),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
