import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/repositories/secure_storage_repository.dart';
import 'dpapi_codec.dart';
import 'profile_secure_storage.dart';

/// Which of several identities on one machine this process belongs to.
///
/// Independent identities are kept apart by namespacing every storage axis —
/// secure storage, the hydrated-state directory, the central session key. The
/// namespace follows the build flavor by default (release = none, debug =
/// `dev`), and `RIFT_PROFILE` overrides it so several same-mode instances can
/// run side by side.
///
/// It lives here rather than in `AppBootstrap` because startup is no longer
/// the only place that needs it: the push background isolate is a second
/// process-like context with none of the app's state, and it has to arrive at
/// the same answer or it reads a different identity's seed.
class StorageNamespace {
  const StorageNamespace._();

  /// Resolve the suffix and point secure storage at it. Returns the suffix;
  /// an empty string is the release default, which keeps existing installs on
  /// their original paths.
  static String apply() {
    final suffix = SecureStorageRepository.resolveSuffix(
      envProfile: explicitProfile,
      releaseMode: kReleaseMode,
    );
    SecureStorageRepository.namespacePrefix =
        SecureStorageRepository.prefixForSuffix(suffix);
    return suffix;
  }

  /// The profile this process was told to be: `RIFT_PROFILE`, or failing that
  /// `--rift-profile=<name>` on the command line. The argument exists for
  /// Windows starting Rift to deliver a notification press, which passes no
  /// environment (`ToastIdentity.launchCommand`). Null for the default.
  static String? get explicitProfile {
    if (kIsWeb) return null;
    final env = Platform.environment['RIFT_PROFILE'];
    if (env != null && env.isNotEmpty) return env;
    return _argumentProfile;
  }

  static String? _argumentProfile;

  /// Takes `--rift-profile=<name>` from the app's arguments. Call from `main`
  /// before anything resolves the namespace.
  static void readArguments(List<String> args) {
    const flag = '--rift-profile=';
    for (final arg in args) {
      if (arg.startsWith(flag) && arg.length > flag.length) {
        _argumentProfile = arg.substring(flag.length);
      }
    }
  }

  /// On Windows, keeps this identity's secure storage in its own folder under
  /// Local AppData rather than the plugin's one file in Roaming AppData (see
  /// [ProfileSecureStorage]). Elsewhere the plugin's own storage stays. Call
  /// after [apply] and before anything reads secure storage.
  static Future<void> useProfileSecureStorage(String suffix) async {
    if (kIsWeb || !Platform.isWindows) return;
    final roaming = (await getApplicationSupportDirectory()).path;
    FlutterSecureStoragePlatform.instance = ProfileSecureStorage(
      File('${await profileDirectory(suffix)}/secure_storage.dat'),
      codec: const DpapiCodec(),
      legacyFile: File('$roaming/flutter_secure_storage.dat'),
      legacyKeys: SecureStorageRepository.namespacedKeys,
    );
  }

  /// Where this identity's files go. Not for web, which has no filesystem —
  /// callers guard on [kIsWeb] and use the browser's own storage instead.
  static Future<String> profileDirectory(String suffix) async {
    final base = (await _baseDirectory()).path;
    return suffix.isEmpty ? base : '$base/rift_$suffix';
  }

  /// The app's own documents folder on mobile and macOS, which are the
  /// app's by construction (sandboxed). On Windows and Linux, "documents" is
  /// the person's own Documents folder. That is somewhere a release build would
  /// scatter its files among theirs, and on Windows it is often synced to
  /// OneDrive, which would upload Rift's state and saved conversations.
  ///
  /// So Windows uses Local AppData (`%LOCALAPPDATA%\com.codingfries\rift`),
  /// which never roams or syncs. path_provider calls it the cache directory,
  /// but Windows does not clear it. Linux uses the XDG data directory
  /// (`~/.local/share/com.codingfries.rift`).
  static Future<Directory> _baseDirectory() {
    if (Platform.isWindows) return getApplicationCacheDirectory();
    if (Platform.isLinux) return getApplicationSupportDirectory();
    return getApplicationDocumentsDirectory();
  }
}
