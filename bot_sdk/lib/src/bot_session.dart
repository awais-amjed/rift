import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:rift/data/repositories/crypto_repository.dart';

/// A bot's connection to one self-hosted Rift server.
///
/// Everything a bot needs to exist: an identity derived from a seed, a session
/// obtained by signing for it, and the two calls that keep it usable. There is
/// no bot API to speak of, which is the point — a bot authenticates the way a
/// person does and is subject to the same policies, so a capability the app has
/// a bot has, and neither can drift away from the other.
class BotSession {
  /// The server's Supabase URL, e.g. `https://abc.supabase.co`.
  final String url;

  /// The server's anon key, returned by `register` when the bot joined.
  final String anonKey;

  /// Which server on that project. Identity is derived per `(host, serverId)`,
  /// so the same seed on two servers is two unrelated bots.
  final String serverId;

  final Uint8List _seed;
  final CryptoRepository _crypto;

  String? _token;
  String? _userId;

  BotSession({
    required this.url,
    required this.anonKey,
    required this.serverId,
    required Uint8List seed,
    CryptoRepository? crypto,
  }) : _seed = seed,
       _crypto = crypto ?? CryptoRepository();

  /// This bot's user id on this server. Null until the first [login].
  String? get userId => _userId;

  /// The app's own crypto, for signing a reply. Exposed rather than wrapped:
  /// a second signing helper is a second thing that can disagree with the
  /// canonical payload, and that disagreement would show up as messages
  /// silently not rendering.
  CryptoRepository get crypto => _crypto;

  /// Sign in, or refresh a session that has expired.
  ///
  /// Cheap enough to call before anything: the key is derived from the seed, so
  /// there is no prompt, no stored refresh token to lose, and no state to
  /// recover if the process restarts. A bot that crashes comes back as itself.
  Future<void> login() async {
    final identity = await _crypto.deriveServerIdentity(
      masterSeed: _seed,
      host: Uri.parse(url).host,
      serverId: serverId,
    );
    final signed = await _crypto.signSiws(
      keyPair: identity.keyPair,
      publicKeyBytes: identity.publicKeyBytes,
    );
    final data = await _function('login', {
      'message': signed.message,
      'signature': signed.signatureBase64,
    });
    _token = data['access_token'] as String;
    _userId = _subjectOf(_token!);
  }

  /// The Ed25519 keypair this bot signs messages with.
  Future<ServerIdentity> identity() => _crypto.deriveServerIdentity(
    masterSeed: _seed,
    host: Uri.parse(url).host,
    serverId: serverId,
  );

  /// Publish what this bot answers to, and what it does with what it is given.
  ///
  /// Worth doing even for a bot with one command. The manifest is how a client
  /// offers `/play` while the bot is asleep, and `dataUse` is shown to somebody
  /// in the composer *before* they type — which for a bot that forwards
  /// anywhere is the sentence that actually matters.
  Future<void> publishManifest(Map<String, dynamic> manifest) =>
      patch('users?id=eq.$_userId', {'manifest': manifest});

  // ── HTTP ──────────────────────────────────────────────────

  /// A PostgREST GET. [query] is everything after the table name, e.g.
  /// `messages?select=id&to_bot=eq.<me>`.
  Future<List<Map<String, dynamic>>> select(String query) async {
    final res = await http.get(
      Uri.parse('$url/rest/v1/$query'),
      headers: _headers,
    );
    _throwIfFailed(res);
    return (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
  }

  /// An insert that hands the row back — needed only where the bot has to
  /// keep the id, which is panels and nothing else so far.
  Future<List<Map<String, dynamic>>> insertReturning(
    String table,
    Map<String, dynamic> row,
  ) async {
    final res = await http.post(
      Uri.parse('$url/rest/v1/$table'),
      headers: {..._headers, 'Prefer': 'return=representation'},
      body: jsonEncode(row),
    );
    _throwIfFailed(res);
    return (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
  }

  Future<void> insert(String table, Map<String, dynamic> row) async {
    final res = await http.post(
      Uri.parse('$url/rest/v1/$table'),
      headers: _headers,
      body: jsonEncode(row),
    );
    _throwIfFailed(res);
  }

  /// Tell anyone with [channelId] open that something happened.
  ///
  /// `new_message` makes a client fetch what is newer than it has; a panel
  /// being redrawn is not newer than anything, so an edit rings
  /// `message_changed` with the row's id instead and the client re-reads that
  /// one. Ringing the wrong one leaves the panel showing the state it had when
  /// the channel was opened — which for the one feature whose entire point is
  /// changing in place is the failure that looks most like it working.
  ///
  /// The app's clients ring this for their own sends, and the `webhook` edge
  /// function rings it for a webhook's. A bot inserting straight into
  /// PostgREST rings nothing — so its reply was stored correctly and reached
  /// nobody until they reopened the channel. Found by watching one not appear.
  ///
  /// Best-effort, and never allowed to fail the reply: the message is already
  /// stored, every client re-reads on open, and the unread badge comes from
  /// the row. A bot that threw because a doorbell did not ring would be
  /// retried by its own error handling and answer twice.
  Future<void> ringDoorbell(
    String channelId, {
    String event = 'new_message',
    Map<String, dynamic> payload = const {},
  }) async {
    try {
      await http.post(
        Uri.parse('$url/realtime/v1/api/broadcast'),
        headers: _headers,
        body: jsonEncode({
          'messages': [
            {'topic': 'chat:$channelId', 'event': event, 'payload': payload},
          ],
        }),
      );
    } catch (_) {}
  }

  Future<void> patch(String query, Map<String, dynamic> patch) async {
    final res = await http.patch(
      Uri.parse('$url/rest/v1/$query'),
      headers: _headers,
      body: jsonEncode(patch),
    );
    _throwIfFailed(res);
  }

  Map<String, String> get _headers => {
    'apikey': anonKey,
    'Authorization': 'Bearer $_token',
    'Content-Type': 'application/json',
    'Prefer': 'return=minimal',
  };

  Future<Map<String, dynamic>> _function(
    String name,
    Map<String, dynamic> body,
  ) async {
    final res = await http.post(
      Uri.parse('$url/functions/v1/$name'),
      headers: {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      },
      body: jsonEncode(body),
    );
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (json['success'] != true) {
      throw BotException('$name failed: ${json['error'] ?? res.body}');
    }
    return (json['data'] as Map).cast<String, dynamic>();
  }

  void _throwIfFailed(http.Response res) {
    if (res.statusCode >= 400) {
      throw BotException('${res.statusCode}: ${res.body}');
    }
  }

  /// The `sub` claim — this bot's user id, which `users.id` is.
  static String _subjectOf(String token) {
    final payload = token.split('.')[1];
    final padded = payload.padRight((payload.length + 3) ~/ 4 * 4, '=');
    return (jsonDecode(utf8.decode(base64Url.decode(padded))) as Map)['sub']
        as String;
  }
}

class BotException implements Exception {
  final String message;
  const BotException(this.message);

  @override
  String toString() => 'BotException: $message';
}
