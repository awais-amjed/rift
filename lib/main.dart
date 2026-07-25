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

import 'package:supabase_flutter/supabase_flutter.dart';

import 'logic/cubits/channel_presence/channel_presence_cubit.dart';
import 'logic/cubits/vault/vault_cubit.dart';
import 'logic/cubits/voice_stats/voice_stats_cubit.dart';
import 'logic/cubits/app/app_cubit.dart';
import 'logic/cubits/central_dm/central_dm_cubit.dart';
import 'logic/cubits/channel_chat/channel_chat_cubit.dart';
import 'logic/cubits/dm/dm_cubit.dart';
import 'logic/cubits/livekit/livekit_cubit.dart';
import 'logic/cubits/notifications/server_notifications_cubit.dart';
import 'logic/cubits/screenshare/screenshare_cubit.dart';
import 'logic/cubits/server/server_cubit.dart';
import 'logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import 'logic/cubits/theme/theme_cubit.dart';
import 'logic/cubits/token/token_cubit.dart';
import 'logic/helper_methods.dart';
import 'logic/ptt/push_to_talk_listener.dart';
import 'logic/services/notification_service.dart';
import 'logic/services/window_focus_service.dart';
import 'logic/services/windows_audio_ducking/windows_audio_ducking.dart';
import 'presentation/common/title_bar_overlay.dart';
import 'presentation/routing/app_routes.dart';
import 'presentation/theme/app_theme.dart';
import 'src/rust/frb_generated.dart';
import 'supabase_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Rust bridge (not supported on web)
  if (!kIsWeb) await RustLib.init();

  // Initialize Supabase for cloud backup session persistence.
  // Dev builds use their own session key so a release + dev instance can run
  // side by side on one machine without sharing the central account session.
  await Supabase.initialize(
    url: SupabaseConfig.supabaseUrl,
    anonKey: SupabaseConfig.supabaseKey,
    authOptions: kReleaseMode
        ? const FlutterAuthClientOptions()
        : FlutterAuthClientOptions(
            localStorage: SharedPreferencesLocalStorage(
              persistSessionKey:
                  'sb-${Uri.parse(SupabaseConfig.supabaseUrl).host.split(".").first}-auth-token-dev',
            ),
          ),
  );

  // Dev builds keep hydrated state in a separate subdirectory for the same
  // reason; release builds keep the original path (existing installs).
  HydratedBloc.storage = await HydratedStorage.build(
    storageDirectory: kIsWeb
        ? HydratedStorageDirectory.web
        : HydratedStorageDirectory(
            kReleaseMode
                ? (await getApplicationDocumentsDirectory()).path
                : '${(await getApplicationDocumentsDirectory()).path}/rift_dev',
          ),
  );

  if (!kIsWeb) {
    await windowManager.ensureInitialized();
    await NotificationService.instance.init();

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
        child: MultiBlocProvider(
          providers: [
            BlocProvider(create: (_) => ThemeCubit()),
            BlocProvider(
              create: (_) {
                final serverCubit = ServerCubit();
                // Wire up VaultCubit so ServerCubit can re-authenticate on token expiry.
                serverCubit.injectVaultCubit(widget.vaultCubit);
                // Wire up a callback so a backup import immediately reconciles the server list.
                widget.vaultCubit.setOnServersImported(
                  serverCubit.syncWithImportedVault,
                );
                // Wire up a callback so export captures the full server list.
                widget.vaultCubit.setGetServersForExport(
                  serverCubit.getServersForExport,
                );
                return serverCubit;
              },
            ),
            BlocProvider.value(value: widget.appCubit),
            BlocProvider.value(value: widget.vaultCubit),
            BlocProvider(create: (_) => TokenCubit()),
            BlocProvider(
              create: (context) {
                final livekitCubit = LiveKitCubit(
                  appCubit: context.read<AppCubit>(),
                  tokenCubit: context.read<TokenCubit>(),
                  // Wire up ServerCubit so LiveKit can re-authenticate on token expiry.
                  serverCubit: context.read<ServerCubit>(),
                );
                return livekitCubit;
              },
            ),
            BlocProvider(
              create: (context) {
                final screenshareCubit = ScreenshareCubit(
                  serverCubit: context.read<ServerCubit>(),
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
            BlocProvider(
              create: (context) => ChannelChatCubit(
                serverCubit: context.read<ServerCubit>(),
                vaultCubit: widget.vaultCubit,
              ),
            ),
            BlocProvider(
              create: (context) => DmCubit(
                serverCubit: context.read<ServerCubit>(),
                vaultCubit: widget.vaultCubit,
              ),
            ),
            BlocProvider(
              create: (context) => CentralDmCubit(
                vaultCubit: widget.vaultCubit,
              ),
            ),
            BlocProvider(
              // Not lazy: the per-server notifications subscription must run
              // whenever a server is selected, not only when a chat view reads it.
              lazy: false,
              create: (context) => ServerNotificationsCubit(
                serverCubit: context.read<ServerCubit>(),
                chatCubit: context.read<ChannelChatCubit>(),
              ),
            ),
            BlocProvider(
              // Not lazy: must exist at startup to receive vault/server change
              // callbacks for cloud auto-backup.
              lazy: false,
              create: (context) {
                final backupCubit = SupabaseBackupCubit(
                  vaultCubit: widget.vaultCubit,
                );
                widget.vaultCubit.setOnVaultChanged(backupCubit.autoBackup);
                context.read<ServerCubit>().setOnServersChanged(
                  backupCubit.autoBackup,
                );
                return backupCubit;
              },
            ),
          ],
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
