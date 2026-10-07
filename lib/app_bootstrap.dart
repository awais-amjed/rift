import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift_crypto/rift_crypto.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:window_manager/window_manager.dart';

import 'data/constants.dart';
import 'data/repositories/native_blob_cipher.dart';
import 'data/repositories/update_repository.dart';
import 'logic/cubits/app/app_cubit.dart';
import 'logic/helper_methods.dart';
import 'logic/services/browser_apis.dart';
import 'logic/services/file_save/save_target.dart';
import 'logic/services/gpu_codecs.dart';
import 'logic/services/host_platform.dart';
import 'logic/services/hydrated_store.dart';
import 'logic/services/invite_scheme.dart';
import 'logic/services/linux_desktop_entry.dart';
import 'logic/services/login_launch/login_launch.dart';
import 'logic/services/notification_service.dart';
import 'logic/services/profile_auth_storage.dart';
import 'logic/services/push_service.dart';
import 'logic/services/sound_service.dart';
import 'logic/services/storage_namespace.dart';
import 'logic/services/text_safety.dart';
import 'logic/services/tray_service/tray_service.dart';
import 'logic/services/window_focus_service.dart';
import 'logic/services/window_placement.dart';
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
    await StorageNamespace.useProfileSecureStorage(storageSuffix);
    _claimInviteLinks(storageSuffix);

    if (!kIsWeb) {
      await RustLib.init();
      CryptoRepository.blobCipher = const NativeBlobCipher();
      // First after the bridge: it may put a downloaded update in place and
      // restart into it, and nothing should have started by then.
      await UpdateRepository.startup();
      // Opening a GPU encoder to see whether it works takes a moment; the
      // share dialog wants the answer the moment it opens.
      GpuCodecs.warmUp();
      // Copies of files a send left behind when the app last closed under
      // it. Not awaited: nothing is being sent yet.
      unawaited(sweepCopies());
    }

    await _initSupabase(storageSuffix);
    await _initHydratedStorage(storageSuffix);

    final appCubit = AppCubit();
    // Every sound reads its mute and volume from here, including the ones
    // raised by services that hold no cubit of their own.
    SoundService.instance.readSettingsFrom(() => appCubit.state.appSounds);
    SoundService.instance.readOutputFrom(() => appCubit.state.outputDeviceId);
    // Desktop, not "not web". window_manager ships no Android or iOS
    // implementation at all, so calling it there is a method channel with
    // nothing on the other end — a MissingPluginException thrown before the
    // first frame. The tray is FFI rather than a channel since tray_manager
    // 0.7, so it fails by handing back no icon instead, but there is no tray
    // on a phone to want one from either.
    if (HostPlatform.drawsOwnWindowChrome) {
      await windowManager.ensureInitialized();
      await _restoreWindow(appCubit);
      await TrayService.instance.init();
      // The runner left the window hidden for a start at sign-in. With no
      // tray to come back from, it waits on the taskbar instead.
      if (LoginLaunch.startedMinimized && !TrayService.instance.isShowing) {
        await windowManager.show();
        await windowManager.minimize();
      }
    }
    // Rewritten at every start, so the entry follows the program if it
    // moves. Not awaited: nothing here waits on it.
    unawaited(appCubit.applyLoginLaunch());
    // Nothing installs Rift on Linux, so it keeps its own app-menu entry:
    // the AppImage always, a folder copy once the person said yes (asked on
    // the home screen). Not awaited: nothing here waits on the menu.
    if (!kIsWeb &&
        Platform.isLinux &&
        (Platform.environment.containsKey('APPIMAGE') ||
            appCubit.state.addToAppMenu == true)) {
      unawaited(LinuxDesktopEntry.ensure());
    }
    // Not desktop-only any more: Android posts these too, and the web posts
    // them through the browser's own Notification API. Asking for the
    // permission at startup beats a system dialog appearing on top of the
    // first message it is about.
    await NotificationService.instance.init();
    // After the local notifications it depends on: a push that arrives during
    // startup is handled by showing one.
    unawaited(PushService.instance.init());
    // The profanity list, for covering flagged messages. Not awaited: until
    // it lands every message is shown, and 60 KB lands before the first one.
    unawaited(TextSafety.instance.load());
    // The web's stand-in for the WindowListener callbacks in main.dart, which
    // window_manager supplies everywhere else. Without it the tab is focused
    // forever and nothing ever notifies, because every trigger site gates on
    // the window being *un*focused.
    if (kIsWeb) {
      startBrowserFocusTracking(WindowFocusService.instance.setFocused);
    }
    return appCubit;
  }

  /// Makes "Open in Rift" on an invite page reach this program, on Windows.
  ///
  /// Only the installed identity claims it. One scheme has one handler, so a
  /// debug build or a second profile claiming it would take every invite the
  /// installed app should get, and keep it after the build was deleted.
  /// A failure costs the button, not the app — pasting an invite still works.
  static void _claimInviteLinks(String storageSuffix) {
    if (kIsWeb || !Platform.isWindows || storageSuffix.isNotEmpty) return;
    try {
      registerInviteScheme(Platform.resolvedExecutable);
    } catch (e) {
      HelperMethods.printDebug('AppBootstrap: invite scheme – $e');
    }
  }

  /// Namespaces this instance's storage. See [StorageNamespace] — the push
  /// background isolate has to reach the same answer, so the rule lives where
  /// both can read it rather than here.
  static String _applyStorageNamespace() => StorageNamespace.apply();

  /// Supabase, for cloud-backup session persistence. A non-empty suffix gives
  /// this instance its own session so it doesn't share the account session
  /// with another instance on the same machine — in a file of the profile's
  /// own, since a key in the shared preferences file was overwritten by the
  /// other profiles (see [ProfileAuthStorage]). The web keeps the key: its
  /// storage is the browser's, and it has no file to give each profile.
  static Future<void> _initSupabase(String storageSuffix) async {
    final host = Uri.parse(SupabaseConfig.supabaseUrl).host.split('.').first;
    final legacyKey = 'sb-$host-auth-token-$storageSuffix';
    final FlutterAuthClientOptions authOptions;
    if (storageSuffix.isEmpty) {
      authOptions = const FlutterAuthClientOptions();
    } else if (kIsWeb) {
      authOptions = FlutterAuthClientOptions(
        localStorage: SharedPreferencesLocalStorage(
          persistSessionKey: legacyKey,
        ),
      );
    } else {
      final directory = await StorageNamespace.profileDirectory(storageSuffix);
      final storage = ProfileAuthStorage(
        File('$directory/central_auth.json'),
        legacySessionKey: legacyKey,
      );
      authOptions = FlutterAuthClientOptions(
        localStorage: storage,
        pkceAsyncStorage: storage,
      );
    }
    await Supabase.initialize(
      url: SupabaseConfig.supabaseUrl,
      publishableKey: SupabaseConfig.supabaseKey,
      authOptions: authOptions,
    );
  }

  /// Hydrated state lives in a per-suffix subdirectory; the release default
  /// keeps the original path so existing installs are untouched.
  static Future<void> _initHydratedStorage(String storageSuffix) async {
    HydratedBloc.storage = await openHydratedStore(
      kIsWeb ? null : await StorageNamespace.profileDirectory(storageSuffix),
    );
  }

  /// Reopens the window where it was last left, with the title bar hidden so
  /// the app can draw its own — kept on a screen that exists now, since the
  /// display it was saved on may since have been unplugged or rescaled.
  static Future<void> _restoreWindow(AppCubit appCubit) async {
    final state = appCubit.state;
    var size = state.windowWidth != null
        ? Size(state.windowWidth!, state.windowHeight!)
        : _defaultWindowSize;
    Offset? position = state.windowX != null
        ? Offset(state.windowX!, state.windowY!)
        : null;

    final screens = await _workAreas();
    if (screens != null) {
      // Nothing saved yet: the window is wherever the platform's runner put
      // it (10,10 on Windows, scaled), which a bigger scale can push the
      // fitted size off the edge from just as well.
      position ??= await _currentPosition();
      (:size, :position) = fitWindowToScreens(
        size: size,
        position: position,
        workAreas: screens.all,
        primary: screens.primary,
      );
    }

    unawaited(
      windowManager.waitUntilReadyToShow(
        WindowOptions(
          titleBarStyle: TitleBarStyle.hidden,
          size: size,
          minimumSize: const Size(K.windowMinWidth, K.windowMinHeight),
        ),
        () async {
          if (position != null) await windowManager.setPosition(position);
        },
      ),
    );
  }

  static Future<Offset?> _currentPosition() async {
    try {
      return await windowManager.getPosition();
    } catch (_) {
      return null;
    }
  }

  /// The displays' usable areas and the primary one, or null when the
  /// platform won't say — then the saved geometry is used as it is.
  static Future<({List<Rect> all, Rect primary})?> _workAreas() async {
    Rect workArea(Display d) =>
        (d.visiblePosition ?? Offset.zero) & (d.visibleSize ?? d.size);
    try {
      final displays = await screenRetriever.getAllDisplays();
      final primary = await screenRetriever.getPrimaryDisplay();
      return (all: displays.map(workArea).toList(), primary: workArea(primary));
    } catch (e) {
      HelperMethods.printDebug('[Window] no display info: $e');
      return null;
    }
  }
}
