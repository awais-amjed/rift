import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase/supabase.dart' hide ErrorCode;

import '../../logic/services/chat_message_ops.dart';
import '../../logic/services/paging.dart';
import '../../logic/services/reaction_ops.dart';
import '../classes/api_response.dart';
import '../classes/member_page.dart';
import '../classes/server_limits.dart';
import '../device_id.dart';
import '../enums/error_code.dart';
import 'server_db.dart';
import 'server_user_row.dart';

part 'server_repository_auth.dart';
part 'server_repository_bots.dart';
part 'server_repository_channels.dart';
part 'server_repository_chat.dart';
part 'server_repository_chat_reads.dart';
part 'server_repository_members.dart';
part 'server_repository_ownership.dart';
part 'server_repository_push.dart';
part 'server_repository_reactions.dart';
part 'server_repository_roles.dart';
part 'server_repository_server.dart';
part 'server_repository_soundboard.dart';
part 'server_repository_unread.dart';
part 'server_repository_voice.dart';
part 'server_repository_webhooks.dart';

/// All I/O against a self-hosted server.
///
/// Two transports, and which one a call uses is not arbitrary. Almost
/// everything is a **direct PostgREST call** under the policies in migration
/// 002 — reading messages, sending one, editing your own, member lists,
/// channels, invites, read cursors. What remains an **edge function** is only
/// what genuinely can't be a table call:
///
///   * it needs a secret the client must never hold — `get_channel_token`
///     (LiveKit API secret), `create_server`, `login` (GoTrue admin grant);
///   * it runs before the caller is a member, or before they have a key at all
///     — `resolve_invite`, `register`;
///   * key distribution (`get_channel_key`, `post_channel_keys`,
///     `sweep_channel_keys`), which enforces the channel-key version race and
///     is deliberately left alone until it can be moved with care.
///
/// Everything else was an endpoint that existed only because clients weren't
/// trusted with the database — which was never a decision, just a consequence
/// of tables without policies.
class ServerRepository
    with
        _AuthApiMixin,
        _BotApiMixin,
        _ChannelApiMixin,
        _ChatApiMixin,
        _ChatReadApiMixin,
        _MemberApiMixin,
        _PushApiMixin,
        _ReactionApiMixin,
        _RoleApiMixin,
        _OwnershipApiMixin,
        _ServerApiMixin,
        _SoundboardApiMixin,
        _UnreadApiMixin,
        _VoiceApiMixin,
        _WebhookApiMixin {
  @override
  final ServerDb _db = ServerDb();

  /// POST to an edge function and normalise its envelope.
  ///
  /// Every part uses it, which is why it is here — the class is the meeting
  /// point for what several mixins share. It is also the only place that knows
  /// the difference between "this server is down" and "this call failed", and
  /// the UI shows very different things for the two.
  @override
  Future<APIResponse> _post(
    String supabaseUrl,
    String functionName,
    Map<String, dynamic> body, {
    String? bearerToken,
  }) async {
    try {
      final uri = Uri.parse('$supabaseUrl/functions/v1/$functionName');
      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              if (bearerToken != null) 'Authorization': 'Bearer $bearerToken',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
      final result = jsonDecode(response.body) as Map<String, dynamic>;
      return _fromSupabaseCF(result);
    } on TimeoutException {
      return APIResponse.error(
        "This server isn't responding — it may be offline. Try again later.",
        errorCode: ErrorCode.serverTimeout,
      );
    } catch (e) {
      // Distinguish "can't reach the server" from other failures so the UI can
      // show a friendly offline message instead of a raw exception.
      final msg = e.toString().toLowerCase();
      final isConnectionError =
          e is http.ClientException ||
          msg.contains('socketexception') ||
          msg.contains('failed host lookup') ||
          msg.contains('connection refused') ||
          msg.contains('connection closed') ||
          msg.contains('network is unreachable');
      if (isConnectionError) {
        return APIResponse.error(
          "Can't reach this server. It may be offline, or check your connection.",
          errorCode: ErrorCode.serverUnreachable,
        );
      }
      return APIResponse.error(e);
    }
  }

  APIResponse _fromSupabaseCF(Map<String, dynamic> data) {
    if (data['success'] == true) {
      return APIResponse.success(data['data']);
    }
    return APIResponse(
      success: false,
      error: data['error'] as String? ?? 'Unknown error',
      errorCode: data['code'] as String?,
    );
  }
}
