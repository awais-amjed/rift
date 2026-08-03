import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:go_router/go_router.dart';
import 'package:keyboard_dismisser/keyboard_dismisser.dart';
import 'package:sizer/sizer.dart';
import 'package:toastification/toastification.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'app_bootstrap.dart';
import 'logic/cubits/app/app_cubit.dart';
import 'logic/cubits/theme/theme_cubit.dart';
import 'logic/cubits/vault/vault_cubit.dart';
import 'logic/helper_methods.dart';
import 'logic/ptt/push_to_talk_listener.dart';
import 'logic/services/window_focus_service.dart';
import 'presentation/app_providers.dart';
import 'presentation/common/title_bar_overlay.dart';
import 'presentation/routing/app_routes.dart';
import 'presentation/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final appCubit = await AppBootstrap.run();
  runApp(MyApp(appCubit: appCubit, vaultCubit: VaultCubit()));
}

/// The app shell: window and tray listeners, the router, and the theme.
/// The cubits it provides are in [AppProviders].
class MyApp extends StatefulWidget {
  final AppCubit appCubit;
  final VaultCubit vaultCubit;

  const MyApp({super.key, required this.appCubit, required this.vaultCubit});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WindowListener, TrayListener {
  late final GoRouter _router = AppRoutes.router(widget.vaultCubit);

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      windowManager.addListener(this);
      trayManager.addListener(this);
    }
    HelperMethods.initEasyLoading();
    widget.vaultCubit.checkVaultStatus();
  }

  @override
  void dispose() {
    if (!kIsWeb) {
      windowManager.removeListener(this);
      trayManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    if (menuItem.key == 'show') {
      await windowManager.show();
      await windowManager.focus();
    } else if (menuItem.key == 'quit') {
      await windowManager.close();
    }
  }

  // Focus tracking drives whether incoming messages raise an OS notification —
  // we only notify while the user isn't looking at the app.
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
              return BlocBuilder<ThemeCubit, ThemeState>(
                builder: (context, themeState) {
                  return PushToTalkListener(
                    child: MaterialApp.router(
                      routerConfig: _router,
                      darkTheme: AppTheme.dark(themeState.palette),
                      theme: AppTheme.light(themeState.palette),
                      themeMode: themeState.themeMode,
                      builder: EasyLoading.init(
                        builder: (context, child) =>
                            TitleBarOverlay(child: child!),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
