import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:go_router/go_router.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:toastification/toastification.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sizer/sizer.dart';
import 'package:keyboard_dismisser/keyboard_dismisser.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'data/repositories/server_repository.dart';
import 'logic/cubits/channel_presence/channel_presence_cubit.dart';
import 'logic/cubits/vault/vault_cubit.dart';
import 'logic/cubits/voice_stats/voice_stats_cubit.dart';
import 'logic/cubits/app/app_cubit.dart';
import 'logic/cubits/livekit/livekit_cubit.dart';
import 'logic/cubits/screenshare/screenshare_cubit.dart';
import 'logic/cubits/server/server_cubit.dart';
import 'logic/cubits/theme/theme_cubit.dart';
import 'logic/cubits/token/token_cubit.dart';
import 'logic/helper_methods.dart';
import 'logic/ptt/push_to_talk_listener.dart';
import 'logic/services/windows_audio_ducking/windows_audio_ducking.dart';
import 'presentation/common/title_bar_overlay.dart';
import 'presentation/routing/app_routes.dart';
import 'presentation/theme/app_theme.dart';
import 'src/rust/frb_generated.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Rust bridge (not supported on web)
  if (!kIsWeb) await RustLib.init();

  HydratedBloc.storage = await HydratedStorage.build(
    storageDirectory: kIsWeb
        ? HydratedStorageDirectory.web
        : HydratedStorageDirectory(
            (await getApplicationDocumentsDirectory()).path,
          ),
  );

  if (!kIsWeb) {
    await windowManager.ensureInitialized();

    final appCubit = AppCubit();
    final windowSize = appCubit.state.windowWidth != null
        ? Size(appCubit.state.windowWidth!, appCubit.state.windowHeight!)
        : const Size(1280, 720);
    final savedPosition = appCubit.state.windowX != null
        ? Offset(appCubit.state.windowX!, appCubit.state.windowY!)
        : null;

    // Apply saved audio ducking preference on startup
    WindowsAudioDucking.apply(disable: appCubit.state.disableAudioDucking);

    windowManager.waitUntilReadyToShow(
      WindowOptions(titleBarStyle: TitleBarStyle.hidden, size: windowSize),
      () async {
        if (savedPosition != null) {
          await windowManager.setPosition(savedPosition);
        }
      },
    );

    await trayManager.setIcon(
      'assets/images/${Platform.isWindows ? 'tray_icon.ico' : 'tray_icon.png'}',
    );
    if (Platform.isWindows) {
      await trayManager.setToolTip('Rift');
    }
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'show', label: 'Show Rift'),
          MenuItem.separator(),
          MenuItem(key: 'quit', label: 'Quit'),
        ],
      ),
    );

    runApp(MyApp(appCubit: appCubit, vaultCubit: VaultCubit()));
  } else {
    runApp(MyApp(appCubit: AppCubit(), vaultCubit: VaultCubit()));
  }
}

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
        child: MultiBlocProvider(
          providers: [
            BlocProvider(create: (_) => ThemeCubit()),
            BlocProvider(create: (_) => ServerCubit()),
            BlocProvider.value(value: widget.appCubit),
            BlocProvider.value(value: widget.vaultCubit),
            BlocProvider(create: (_) => TokenCubit()),
            BlocProvider(
              create: (context) {
                // Create both cubits together to handle cross-references
                final appCubit = context.read<AppCubit>();
                final livekitCubit = LiveKitCubit(
                  repository: ServerRepository(),
                  appCubit: appCubit,
                  tokenCubit: context.read<TokenCubit>(),
                );
                return livekitCubit;
              },
            ),
            BlocProvider(
              create: (context) {
                final screenshareCubit = ScreenshareCubit(
                  repository: ServerRepository(),
                  livekitCubit: context.read<LiveKitCubit>(),
                );
                // Wire up screenshare cubit for automatic cleanup on disconnect
                context.read<LiveKitCubit>().setScreenshareCubit(
                  screenshareCubit,
                );
                return screenshareCubit;
              },
            ),
            BlocProvider(
              create: (context) =>
                  VoiceStatsCubit(livekitCubit: context.read<LiveKitCubit>()),
            ),
            BlocProvider(
              create: (context) => ChannelPresenceCubit(
                serverCubit: context.read<ServerCubit>(),
                livekitCubit: context.read<LiveKitCubit>(),
              ),
            ),
          ],
          child: Sizer(
            builder: (context, orientation, screenType) {
              return BlocBuilder<ThemeCubit, ThemeState>(
                builder: (context, themeState) {
                  return PushToTalkListener(
                    child: MaterialApp.router(
                      routerConfig: _router,
                      darkTheme: AppTheme.darkTheme,
                      theme: AppTheme.lightTheme,
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
