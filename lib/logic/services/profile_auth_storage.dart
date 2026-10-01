import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One profile's central session, and Auth's sign-in scratch values, in a file
/// of that profile's own.
///
/// Profiles (`RIFT_PROFILE`) used to keep their session in the one
/// shared_preferences file every profile on the machine shares, under a key of
/// their own. The key was not enough: on Windows (and Linux) the plugin reads
/// that file once and writes its whole cached copy back on every change, so a
/// profile that saved anything wrote back a copy taken before the others had
/// saved theirs. One client signing up erased the session another had stored a
/// moment earlier, and that one came back signed out at its next launch. The
/// PKCE values Auth keeps during a sign-in went through the same file, and
/// could do the same.
///
/// Only profiles use this; the release default keeps its original storage, so
/// existing installs are untouched.
class ProfileAuthStorage extends LocalStorage implements GotrueAsyncStorage {
  final File _file;

  /// The key this profile's session was kept under in shared_preferences,
  /// read once when this profile has no file yet so nobody is signed out by
  /// the move.
  final String? _legacySessionKey;

  ProfileAuthStorage(this._file, {String? legacySessionKey})
    : _legacySessionKey = legacySessionKey;

  static const String _sessionKey = 'session';
  static const String _pkcePrefix = 'pkce:';

  Map<String, String> _values = {};
  Future<void>? _loading;

  /// Reads the file once; every method waits for it, since Auth may ask for a
  /// PKCE value through a path that does not call [initialize] first.
  Future<void> _ready() => _loading ??= _load();

  Future<void> _load() async {
    if (await _file.exists()) {
      try {
        final decoded = jsonDecode(await _file.readAsString());
        if (decoded is Map) {
          _values = decoded.map((k, v) => MapEntry('$k', '$v'));
        }
      } on FormatException {
        // A torn or foreign file is treated as empty: signed out, which is
        // recoverable, rather than a launch that fails.
        _values = {};
      }
      return;
    }
    final legacyKey = _legacySessionKey;
    if (legacyKey == null) return;
    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString(legacyKey);
    if (legacy == null) return;
    _values[_sessionKey] = legacy;
    await _write();
    await prefs.remove(legacyKey);
  }

  /// Through a temporary file and a rename, so a crash mid-write leaves the
  /// old session rather than half of one.
  Future<void> _write() async {
    await _file.parent.create(recursive: true);
    final temp = File('${_file.path}.tmp');
    await temp.writeAsString(jsonEncode(_values), flush: true);
    await temp.rename(_file.path);
  }

  Future<void> _set(String key, String? value) async {
    await _ready();
    if (value == null) {
      if (_values.remove(key) == null) return;
    } else {
      _values[key] = value;
    }
    await _write();
  }

  @override
  Future<void> initialize() => _ready();

  @override
  Future<bool> hasAccessToken() async {
    await _ready();
    return _values.containsKey(_sessionKey);
  }

  @override
  Future<String?> accessToken() async {
    await _ready();
    return _values[_sessionKey];
  }

  @override
  Future<void> persistSession(String persistSessionString) =>
      _set(_sessionKey, persistSessionString);

  @override
  Future<void> removePersistedSession() => _set(_sessionKey, null);

  @override
  Future<String?> getItem({required String key}) async {
    await _ready();
    return _values['$_pkcePrefix$key'];
  }

  @override
  Future<void> setItem({required String key, required String value}) =>
      _set('$_pkcePrefix$key', value);

  @override
  Future<void> removeItem({required String key}) =>
      _set('$_pkcePrefix$key', null);
}
