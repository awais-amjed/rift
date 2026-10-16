import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../helper_methods.dart';

/// shared_preferences' file on Windows and Linux, set aside when it cannot be
/// read.
///
/// The plugin keeps every preference in one JSON file and rewrites it in
/// place, so a PC that loses power mid-write can leave it full of zeros. The
/// plugin's read then throws, and so did `Supabase.initialize`, whose central
/// session lived there: the start ended before the first frame and the window
/// stayed white, every launch, through any number of reinstalls (the file is
/// in Roaming AppData, which an uninstall leaves). The session has its own
/// file now (`ProfileAuthStorage`), but its first start still reads the old
/// one to move the session over, and the emoji picker keeps its recent
/// emojis there. Set aside, the file costs those and nothing else.
class PreferencesFile {
  const PreferencesFile._();

  /// Call before anything opens shared_preferences.
  static Future<void> setAsideIfUnreadable() async {
    if (kIsWeb || !(Platform.isWindows || Platform.isLinux)) return;
    try {
      // The folder and name both plugins read (`getApplicationSupportPath`,
      // `shared_preferences.json`).
      final directory = await getApplicationSupportDirectory();
      await check(File('${directory.path}/shared_preferences.json'));
    } catch (e) {
      HelperMethods.printDebug('[Preferences] not checked: $e');
    }
  }

  /// Moves [file] to `<name>.unreadable` when it holds something the plugin
  /// would fail on, and says whether it did. Not deleted, as with
  /// `ProfileSecureStorage`: the bytes stay for whoever can make sense of
  /// them.
  @visibleForTesting
  static Future<bool> check(File file) async {
    if (!await file.exists()) return false;
    try {
      // The plugin's own test: an empty file is no preferences, not a fault.
      final text = await file.readAsString();
      if (text.isEmpty) return false;
      jsonDecode(text);
      return false;
    } on FormatException {
      // Not JSON.
    } on FileSystemException {
      // Not UTF-8, which is how a read of torn bytes fails.
    }
    HelperMethods.printDebug(
      '[Preferences] ${file.uri.pathSegments.last} unreadable; set aside, '
      'central signs in again',
    );
    try {
      await file.rename('${file.path}.unreadable');
    } on FileSystemException {
      await file.delete();
    }
    return true;
  }
}
