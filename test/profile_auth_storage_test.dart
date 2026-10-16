import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/profile_auth_storage.dart';
import 'package:rift/logic/services/push_wake/wake_central_reader.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Profiles side by side used to share one preferences file, and each wrote
/// its stale copy over the others' sessions. Each now has a file of its own.
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('profile_auth_');
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => dir.delete(recursive: true));

  File fileFor(String profile) => File('${dir.path}/rift_$profile/auth.json');

  test('a session is kept, read back after a restart, and removed', () async {
    final storage = ProfileAuthStorage(fileFor('wa'));
    await storage.initialize();
    expect(await storage.hasAccessToken(), isFalse);

    await storage.persistSession('session-a');
    final reopened = ProfileAuthStorage(fileFor('wa'));
    await reopened.initialize();
    expect(await reopened.accessToken(), 'session-a');

    await reopened.removePersistedSession();
    final again = ProfileAuthStorage(fileFor('wa'));
    expect(await again.hasAccessToken(), isFalse);
  });

  test('two profiles writing in turn keep each other\'s sessions', () async {
    // The failure this replaces: B, started before A saved, saving after it.
    final a = ProfileAuthStorage(fileFor('wa'));
    final b = ProfileAuthStorage(fileFor('wb'));
    await a.initialize();
    await b.initialize();
    await a.persistSession('session-a');
    await b.persistSession('session-b');

    expect(await ProfileAuthStorage(fileFor('wa')).accessToken(), 'session-a');
    expect(await ProfileAuthStorage(fileFor('wb')).accessToken(), 'session-b');
  });

  test('PKCE values sit beside the session without touching it', () async {
    final storage = ProfileAuthStorage(fileFor('wa'));
    await storage.persistSession('session-a');
    await storage.setItem(key: 'session', value: 'verifier');
    expect(await storage.getItem(key: 'session'), 'verifier');
    expect(await storage.accessToken(), 'session-a');

    await storage.removeItem(key: 'session');
    expect(await storage.getItem(key: 'session'), isNull);
    expect(await storage.accessToken(), 'session-a');
  });

  test('a torn file reads as signed out rather than failing', () async {
    final file = fileFor('wa');
    await file.parent.create(recursive: true);
    await file.writeAsString('{"session": "half');
    final storage = ProfileAuthStorage(file);
    await storage.initialize();
    expect(await storage.hasAccessToken(), isFalse);
  });

  test('a session under the old shared key moves over once', () async {
    SharedPreferences.setMockInitialValues({'sb-x-auth-token-wa': 'old'});
    final storage = ProfileAuthStorage(
      fileFor('wa'),
      legacySessionKey: 'sb-x-auth-token-wa',
    );
    expect(await storage.accessToken(), 'old');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('sb-x-auth-token-wa'), isNull);

    // With the file there, the old key is never read again.
    SharedPreferences.setMockInitialValues({'sb-x-auth-token-wa': 'stale'});
    final reopened = ProfileAuthStorage(
      fileFor('wa'),
      legacySessionKey: 'sb-x-auth-token-wa',
    );
    expect(await reopened.accessToken(), 'old');
  });

  test('the release default moves the session supabase_flutter kept', () async {
    // supabase_flutter's own key: "sb-" + the first label of the host. Spelt
    // wrong, every Windows and Linux install is signed out of central by the
    // update.
    final key = WakeCentralReader.sessionKey('');
    expect(key, 'sb-api-auth-token');
    SharedPreferences.setMockInitialValues({key: 'session', 'recent': 'x'});
    final storage = ProfileAuthStorage(
      File('${dir.path}/central_auth.json'),
      legacySessionKey: key,
    );
    expect(await storage.accessToken(), 'session');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(key), isNull);
    expect(prefs.getString('recent'), 'x');
  });
}
