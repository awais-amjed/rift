import 'dart:convert';
import 'dart:typed_data';

import 'package:rift_crypto/rift_crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase/supabase.dart';

import '../../../data/enums/notification_level.dart';
import '../../../supabase_config.dart';
import 'wake_dm_scan.dart';
import 'wake_item.dart';
import 'wake_marks.dart';

/// Reading central DMs from the push background isolate.
///
/// Unlike a self-hosted server, central cannot be signed into from the seed:
/// the account there is an email and a password the user typed, and neither is
/// on the device. So this uses the session the app already persisted — and
/// uses it **inertly**. It reads the stored access token, checks it has not
/// expired, and talks to central with a bare client that has no auth state of
/// its own.
///
/// It must not go through Supabase's own client for this. That would recover
/// the session, notice it was near expiry, refresh it, and write back a
/// rotated refresh token — leaving the app, which may still be running in the
/// background with the old one in memory, signed out at its next refresh. The
/// price of staying inert is that a token older than an hour cannot be used,
/// and central falls back to the doorbell it would have rung anyway.
class WakeCentralReader {
  final CryptoRepository _crypto;
  final WakeDmScan _dms;

  WakeCentralReader({CryptoRepository? crypto, WakeDmScan? dms})
    : _crypto = crypto ?? CryptoRepository(),
      _dms = dms ?? WakeDmScan(crypto: crypto);

  /// Every conversation on central is with one person, so a wake here speaks
  /// about at most this many of them — the same ceiling a server gets.
  static const maxScopes = 5;

  /// Where `supabase_flutter` persists the session, spelled the same way it
  /// spells it. A non-empty [suffix] is one of several identities sharing a
  /// device, which the app gives its own session key.
  static String sessionKey(String suffix) {
    final host = Uri.parse(SupabaseConfig.supabaseUrl).host.split('.').first;
    return suffix.isEmpty
        ? 'sb-$host-auth-token'
        : 'sb-$host-auth-token-$suffix';
  }

  /// What is new in central DMs. Empty when there is no usable session, which
  /// is not a failure — it is the ordinary state of an account that has not
  /// been opened in over an hour.
  Future<WakeHarvest> read(
    Uint8List seed,
    WakeMarks marks, {
    required String storageSuffix,
  }) async {
    final session = await _session(storageSuffix);
    // Not a failure. An account nobody has opened in over an hour has no
    // usable token, which is the ordinary state of one — and there is nothing
    // to fall back to saying, because the doorbell may not have been about
    // central at all.
    if (session == null) return emptyHarvest;

    final client = SupabaseClient(
      SupabaseConfig.supabaseUrl,
      SupabaseConfig.supabaseKey,
      headers: {
        'apikey': SupabaseConfig.supabaseKey,
        'Authorization': 'Bearer ${session.accessToken}',
      },
    );
    try {
      final counts = await client.rpc('unread_counts');
      final unread = _unreadDms(counts);
      if (unread.isEmpty) return emptyHarvest;

      // Levels arrive with the counts (central migration 011), so a muted
      // conversation is dropped here as well as at the ring trigger — a wake
      // caused by somebody else must not speak for it on the way past.
      final prefs = counts is Map ? counts['prefs'] : null;
      final levels = NotificationLevel.mapFrom(
        prefs is Map ? prefs['dms'] : null,
        fallback: NotificationLevel.dmDefault,
      );

      final conversations = await client.rpc('dm_conversations');
      if (conversations is! List) return failedHarvest;

      final identity = await _crypto.deriveChatIdentity(
        masterSeed: seed,
        host: Uri.parse(SupabaseConfig.supabaseUrl).host,
        version: CryptoRepository.chatIdentityVersion,
      );

      return (
        items: await _dms.scan(
          conversations: conversations.cast<Map<String, dynamic>>(),
          unread: unread,
          myUserId: session.userId,
          myChatKeyPair: identity.keyPair,
          scopePrefix: 'central',
          marks: marks,
          levels: levels,
          limit: maxScopes,
        ),
        failed: false,
      );
    } catch (_) {
      return failedHarvest;
    } finally {
      await client.dispose();
    }
  }

  static Map<String, int> _unreadDms(dynamic counts) {
    final dms = counts is Map ? counts['dms'] : null;
    if (dms is! Map) return const {};
    return {
      for (final entry in dms.entries)
        if (entry.value is int && (entry.value as int) > 0)
          '${entry.key}': entry.value as int,
    };
  }

  /// The stored session, if there is one and it is still good for a moment
  /// longer. Nothing here writes: an expired token is simply no token.
  Future<_WakeSession?> _session(String suffix) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(sessionKey(suffix));
      if (raw == null) return null;
      return _WakeSession.parse(raw);
    } catch (_) {
      return null;
    }
  }
}

/// The two things a wake needs out of a persisted session.
class _WakeSession {
  final String accessToken;
  final String userId;

  const _WakeSession({required this.accessToken, required this.userId});

  /// Null unless the token is present and has at least [_margin] left. The
  /// margin covers the round trips this wake is about to make, so a token that
  /// expires mid-read fails before the work rather than during it.
  static const _margin = Duration(seconds: 30);

  static _WakeSession? parse(String raw) {
    final json = jsonDecode(raw);
    if (json is! Map) return null;
    final token = json['access_token'];
    final expiresAt = json['expires_at'];
    final userId = (json['user'] as Map?)?['id'];
    if (token is! String || userId is! String || expiresAt is! int) return null;

    final expiry = DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000);
    if (expiry.isBefore(DateTime.now().add(_margin))) return null;
    return _WakeSession(accessToken: token, userId: userId);
  }
}
