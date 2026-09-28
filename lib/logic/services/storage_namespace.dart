import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/repositories/secure_storage_repository.dart';

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
      envProfile: kIsWeb ? null : Platform.environment['RIFT_PROFILE'],
      releaseMode: kReleaseMode,
    );
    SecureStorageRepository.namespacePrefix =
        SecureStorageRepository.prefixForSuffix(suffix);
    return suffix;
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
