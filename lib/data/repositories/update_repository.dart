import 'package:flutter/foundation.dart';

import '../../logic/helper_methods.dart';
import '../../src/rust/api/updater.dart' as rust;

/// Rift replacing itself with a newer release, through the Rust side's
/// Velopack (`rust/src/updater`).
///
/// Only a copy Rift's own installer (Windows) or AppImage (Linux) put in
/// place can do this: anything else — a build run from its folder, the
/// `.tar.gz`, the old Windows installer's copy — has [installedVersion] null.
class UpdateRepository {
  const UpdateRepository();

  /// The version this copy was installed as, or null when it cannot update
  /// itself. Known once [startup] has run.
  static String? get installedVersion => _installedVersion;
  static String? _installedVersion;

  /// Velopack's start-up, run once as early as the bridge allows. If an
  /// update was downloaded in a run that quit without restarting for it, this
  /// puts it in place and starts the new version — and this process ends
  /// before it returns.
  static Future<void> startup() async {
    if (kIsWeb) return;
    try {
      _installedVersion = await rust.updaterStartup();
    } catch (e) {
      HelperMethods.printDebug('UpdateRepository: startup – $e');
    }
  }

  /// The newest release after this one, or null when there is none.
  /// Pre-releases count when [includePrereleases]. Throws when the releases
  /// cannot be read.
  Future<rust.AvailableUpdate?> check({required bool includePrereleases}) =>
      rust.updaterCheck(includePrereleases: includePrereleases);

  /// Downloads what the last [check] found: progress from 0 to 100, ending
  /// when the update is ready, or with an error.
  Stream<int> download() => rust.updaterDownload();

  /// Hands the downloaded update to the updater, which waits for this
  /// process to end, puts the update in place and starts Rift again.
  Future<void> applyOnExit() => rust.updaterApplyOnExit();
}
