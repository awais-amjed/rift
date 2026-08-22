import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'data/repositories/secure_storage_repository.dart';
import 'logic/cubits/app/app_cubit.dart';
import 'logic/services/host_platform.dart';
import 'logic/services/notification_service.dart';
import 'logic/services/windows_audio_ducking/windows_audio_ducking.dart';
import 'src/rust/frb_generated.dart';
import 'supabase_config.dart';

/// Everything that must happen before the first frame: storage namespacing,
/// the Rust bridge, Supabase, hydrated state, and the desktop window and tray.
class AppBootstrap {
  const AppBootstrap._();

  static const _defaultWindowSize = Size(1280, 720);

  /// Prepares storage and services, and returns the [AppCubit] that the
  /// window setup already read its saved geometry from — so the app doesn't
  /// build a second one with different state.
  static Future<AppCubit> run() async {
    final storageSuffix = _applyStorageNamespace();

    if (!kIsWeb) await RustLib.init();

    await _initSupabase(storageSuffix);
    await _initHydratedStorage(storageSuffix);

    final appCubit = AppCubit();
    // Desktop, not "not web". window_manager and tray_manager ship no Android
    // or iOS implementation at all, so every one of these is a method channel
    // with nothing on the other end — a MissingPluginException thrown before
    // the first frame.
    if (HostPlatform.drawsOwnWindowChrome) {
      await windowManager.ensureInitialized();
      WindowsAudioDucking.apply(disable: appCubit.state.disableAudioDucking);
      _restoreWindow(appCubit);
      await _initTray();
    }
    // Not desktop-only any more: Android posts these too, and asking for the
    // permission at startup beats a system dialog appearing on top of the
    // first message it is about.
    if (!kIsWeb) await NotificationService.instance.init();
    return appCubit;
  }

  /// Independent identities on one machine are kept apart by namespacing every
  /// storage axis (secure storage, HydratedBloc directory, central session
  /// key). This follows the build flavor by default (release = none, debug =
  /// "dev"), but `RIFT_PROFILE` overrides it so several same-mode instances can
  /// run side by side — `RIFT_PROFILE=a ./rift` and `RIFT_PROFILE=b ./rift`.
  ///
  /// Returns the suffix; an empty string is the release default, which keeps
  /// existing installs on their original paths.
  static String _applyStorageNamespace() {
    final suffix = SecureStorageRepository.resolveSuffix(
      envProfile: kIsWeb ? null : Platform.environment['RIFT_PROFILE'],
      releaseMode: kReleaseMode,
    );
    SecureStorageRepository.namespacePrefix =
        SecureStorageRepository.prefixForSuffix(suffix);
    return suffix;
  }

  /// Supabase, for cloud-backup session persistence. A non-empty suffix gives
  /// this instance its own session key so it doesn't share the account session
  /// with another instance on the same machine.
  static Future<void> _initSupabase(String storageSuffix) {
    final host = Uri.parse(SupabaseConfig.supabaseUrl).host.split('.').first;
    return Supabase.initialize(
      url: SupabaseConfig.supabaseUrl,
      publishableKey: SupabaseConfig.supabaseKey,
      authOptions: storageSuffix.isEmpty
          ? const FlutterAuthClientOptions()
          : FlutterAuthClientOptions(
              localStorage: SharedPreferencesLocalStorage(
                persistSessionKey: 'sb-$host-auth-token-$storageSuffix',
              ),
            ),
    );
  }

  /// Hydrated state lives in a per-suffix subdirectory; the release default
  /// keeps the original path so existing installs are untouched.
  static Future<void> _initHydratedStorage(String storageSuffix) async {
    HydratedStorageDirectory directory;
    if (kIsWeb) {
      directory = HydratedStorageDirectory.web;
    } else {
      final base = (await getApplicationDocumentsDirectory()).path;
      directory = HydratedStorageDirectory(
        storageSuffix.isEmpty ? base : '$base/rift_$storageSuffix',
      );
    }
    HydratedBloc.storage = await HydratedStorage.build(
      storageDirectory: directory,
    );
  }

  /// Reopens the window where it was last left, with the title bar hidden so
  /// the app can draw its own.
  static void _restoreWindow(AppCubit appCubit) {
    final state = appCubit.state;
    final size = state.windowWidth != null
        ? Size(state.windowWidth!, state.windowHeight!)
        : _defaultWindowSize;
    final position = state.windowX != null
        ? Offset(state.windowX!, state.windowY!)
        : null;

    windowManager.waitUntilReadyToShow(
      WindowOptions(titleBarStyle: TitleBarStyle.hidden, size: size),
      () async {
        if (position != null) await windowManager.setPosition(position);
      },
    );
  }

  static Future<void> _initTray() async {
    await trayManager.setIcon(
      'assets/images/${Platform.isWindows ? 'tray_icon.ico' : 'tray_icon.png'}',
    );
    if (Platform.isWindows) await trayManager.setToolTip('Rift');
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'show', label: 'Show Rift'),
          MenuItem.separator(),
          MenuItem(key: 'quit', label: 'Quit'),
        ],
      ),
    );
  }
}
