import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../logic/services/chat_message_ops.dart';
import '../../logic/services/paging.dart';
import '../classes/api_response.dart';
import '../classes/friend.dart';
import '../classes/friend_buckets.dart';
import '../classes/paged.dart';
import '../enums/friendship_state.dart';
import '../enums/notification_level.dart';
import 'attachment_repository.dart';

part 'central_dm_repository_attachments.dart';
part 'central_dm_repository_directory.dart';
part 'central_dm_repository_friends.dart';
part 'central_dm_repository_prefs.dart';
part 'central_dm_repository_push.dart';
part 'central_dm_repository_read_state.dart';

/// Turns a Postgres error raised by an RPC into a failure carrying its *code*.
///
/// Central's RPCs signal by `RAISE EXCEPTION 'quota_exceeded'`, which arrives
/// as prose with the name somewhere inside it. Matching for the name is how a
/// caller tells a rule it broke from a network that fell over — and it lives
/// here, once, because both the send path and every friends RPC need it and
/// two copies of a list of error codes is two lists that drift.
APIResponse _rpcFailure(PostgrestException e, List<String> known) {
  final code = known.firstWhere(
    (candidate) => e.message.contains(candidate),
    orElse: () => '',
  );
  return APIResponse(
    success: false,
    error: code.isNotEmpty ? code : e.message,
    errorCode: code.isNotEmpty ? code : null,
  );
}

/// Central-server DM I/O (Stage 3 — the discovery/first-contact tier,
/// ARCHITECTURE.md §4). Everything runs over the central Supabase client with
/// the user's GoTrue session: RLS scopes reads, and writes go through the
/// quota-enforcing `send_dm` RPC. Content is E2E — this repository only moves
/// opaque envelopes and directory rows.
class CentralDmRepository
    with
        _CentralDmAttachmentsMixin,
        _CentralDmPushMixin,
        _CentralDmDirectoryMixin,
        _CentralDmFriendsMixin,
        _CentralDmPrefsMixin,
        _CentralDmReadStateMixin {
  @override
  SupabaseClient get _client => Supabase.instance.client;

  /// Encrypt/decrypt for attachment blobs (bytes moved over the central SDK).
  @override
  final AttachmentRepository _attachments = AttachmentRepository();

  User? get currentUser => _client.auth.currentUser;

  Stream<AuthState> get authChanges => _client.auth.onAuthStateChange;

  // ──────────────────────────────────────────────────────────
  // Messages
  // ──────────────────────────────────────────────────────────

  /// Send one envelope through the quota-enforcing RPC. Returns
  /// `{id, created_at, state, remaining, quota}`; quota exhaustion surfaces as
  /// errorCode `quota_exceeded`.
  ///
  /// `not_friends` is the gate, and it is the only refusal the friendship can
  /// produce: a stranger, an unanswered request in either direction, somebody
  /// unfriended, somebody who blocked you and somebody you blocked all come
  /// back the same way. Which of those it is — a block especially — is not the
  /// sender's to learn from a bounce.
  ///
  /// `state` is where the pair stands after the send, and is always `friends`
  /// because nothing else gets that far. The caller compares it with what this
  /// device believes and re-reads the graph when they differ, which is how a
  /// client that missed a Realtime frame notices.
  Future<APIResponse> sendDm({
    required String recipientId,
    required Map<String, dynamic> envelope,
  }) async {
    try {
      final result = await _client.rpc(
        'send_dm',
        params: {
          'recipient': recipientId,
          'ciphertext': envelope['ciphertext'],
          'nonce': envelope['nonce'],
          'signature': envelope['signature'],
          'key_version': envelope['key_version'],
        },
      );
      return APIResponse.success(result);
    } on PostgrestException catch (e) {
      return _rpcFailure(e, const [
        'quota_exceeded',
        'recipient_has_no_profile',
        'sender_has_no_profile',
        'cannot_dm_self',
        'envelope_invalid',
        // The friends gate. One code for every way of not being friends.
        'not_friends',
      ]);
    } catch (e) {
      return APIResponse.error(e);
    }
  }

  /// The caller's remaining daily quota: `{quota, remaining}`.
  Future<APIResponse> getQuota() async {
    try {
      final result = await _client.rpc('dm_quota');
      return APIResponse.success(result);
    } catch (e) {
      return APIResponse.error(e);
    }
  }

  /// Replace one envelope in place (sender only — enforced by RLS *and* the
  /// `sender_id` filter). Central DMs write straight to the table rather than
  /// through the quota RPC: an edit isn't a new message, so it must not cost
  /// quota. Returns the new `edited_at`.
  Future<APIResponse> editDm({
    required int messageId,
    required Map<String, dynamic> envelope,
  }) async {
    try {
      final myId = _client.auth.currentUser!.id;
      final editedAt = DateTime.now().toUtc().toIso8601String();
      final rows = await _client
          .from('dm_messages')
          .update({
            'ciphertext': envelope['ciphertext'],
            'nonce': envelope['nonce'],
            'signature': envelope['signature'],
            'key_version': envelope['key_version'],
            'edited_at': editedAt,
          })
          .eq('id', messageId)
          .eq('sender_id', myId)
          .select('id, edited_at');
      if ((rows as List).isEmpty) {
        return APIResponse.error('Message not found, or not yours to change');
      }
      return APIResponse.success(rows.first);
    } catch (e) {
      return APIResponse.error(e);
    }
  }

  /// Hard-delete one envelope (sender only). Removes it for the peer too —
  /// there is a single row per message.
  Future<APIResponse> deleteDm({required int messageId}) async {
    try {
      final myId = _client.auth.currentUser!.id;
      final rows = await _client
          .from('dm_messages')
          .delete()
          .eq('id', messageId)
          .eq('sender_id', myId)
          .select('id');
      if ((rows as List).isEmpty) {
        return APIResponse.error('Message not found, or not yours to change');
      }
      return APIResponse.success(rows.first);
    } catch (e) {
      return APIResponse.error(e);
    }
  }

  /// Page through the conversation with [peerId] (RLS already restricts rows
  /// to the caller's own conversations).
  ///
  /// Answers `{messages, has_more}`, the same shape the self-hosted reads use.
  Future<APIResponse> listDms({
    required String peerId,
    int? beforeId,
    int? afterId,
    int limit = ChatMessageOps.pageSize,
  }) async {
    try {
      final myId = _client.auth.currentUser!.id;
      var query = _client
          .from('dm_messages')
          .select()
          .or(
            'and(sender_id.eq.$myId,recipient_id.eq.$peerId),'
            'and(sender_id.eq.$peerId,recipient_id.eq.$myId)',
          );
      if (afterId != null) query = query.gt('id', afterId);
      if (beforeId != null) query = query.lt('id', beforeId);
      // One row past the page — see Paging.split.
      final rows = await query
          .order('id', ascending: afterId != null)
          .limit(limit + 1);
      final page = Paging.split(
        (rows as List).cast<Map<String, dynamic>>(),
        limit: limit,
      );
      return APIResponse.success({
        'messages': page.rows,
        'has_more': page.hasMore,
      });
    } catch (e) {
      return APIResponse.error(e);
    }
  }

  /// One page of the caller's conversations, newest first (central migration
  /// 013).
  ///
  /// Answers `{conversations, has_more}`, and each conversation carries
  /// everything its row draws: the peer and their published keys, the newest
  /// envelope, the unread count, the newest inbound id a "mark read" writes
  /// back, and the notification level.
  ///
  /// This replaced four unbounded reads. The list used to be derived on the
  /// client from the last thousand envelopes, with the read cursors and the
  /// notification levels fetched whole beside them — so past a thousand
  /// messages an old conversation fell off the list silently, taking its unread
  /// badge with it, and there was no cursor with which to ask for more.
  ///
  /// [before] is the previous page's last `last_message.id`. Keyset rather than
  /// an offset: a conversation moves to the top when somebody speaks in it, and
  /// an offset under that would skip and repeat rows at every boundary.
  Future<APIResponse> listConversations({int limit = 30, int? before}) async {
    try {
      final result = await _client.rpc(
        'dm_conversations',
        params: {'p_limit': limit, 'p_before': before},
      );
      return APIResponse.success(result);
    } catch (e) {
      return APIResponse.error(e);
    }
  }

  // ──────────────────────────────────────────────────────────
  // Realtime
  // ──────────────────────────────────────────────────────────

  /// Subscribe to DMs addressed to the caller: [onInsert] for a new one,
  /// [onUpdate] with the row id when one is edited.
  ///
  /// Deletes are absent on purpose. A DELETE event carries only the primary
  /// key, so the `recipient_id` filter can't match it — subscribing would mean
  /// hearing about every deletion on the tier, by everyone. A deleted central
  /// DM therefore disappears when the conversation is next opened.
  RealtimeChannel subscribeIncoming(
    void Function() onInsert, {
    required void Function(String messageId) onUpdate,
    required void Function() onPrefsChanged,
    required void Function() onGraphChanged,
  }) {
    final myId = _client.auth.currentUser!.id;
    final mine = PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'recipient_id',
      value: myId,
    );
    final channel = _client.channel('central-dm-incoming')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'dm_messages',
        filter: mine,
        callback: (_) => onInsert(),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'dm_messages',
        filter: mine,
        callback: (payload) {
          final id = payload.newRecord['id'];
          if (id != null) onUpdate('$id');
        },
      )
      // A level set on another device. Same channel rather than a second one:
      // it is the same account watching its own rows, and a subscription costs
      // a connection whether or not anything ever comes down it.
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'notification_prefs',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: myId,
        ),
        callback: (_) => onPrefsChanged(),
      )
      // A request answered on a phone has to reach the desktop, or the
      // relationship is per-device state that happens to live on a server.
      //
      // Two bindings for one table because a Realtime filter is one column and
      // `friendships` is keyed by a *pair* — the caller is `low_id` in half
      // their rows and `high_id` in the other half. Both land on this channel:
      // it is the same account watching its own rows, and a subscription costs
      // a connection whether or not anything comes down it.
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'friendships',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'low_id',
          value: myId,
        ),
        callback: (_) => onGraphChanged(),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'friendships',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'high_id',
          value: myId,
        ),
        callback: (_) => onGraphChanged(),
      )
      // Only our own blocks. There is no policy anywhere that lets the blocked
      // side read the row, so a `blocked_id` binding would deliver nothing and
      // advertise the attempt.
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'blocks',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'blocker_id',
          value: myId,
        ),
        callback: (_) => onGraphChanged(),
      )
      ..subscribe();
    return channel;
  }

  /// One DM by id, or `{message: null}` when it is gone. The single-row read
  /// behind an edit notification.
  Future<APIResponse> getDm({required int messageId}) async {
    try {
      final row = await _client
          .from('dm_messages')
          .select()
          .eq('id', messageId)
          .maybeSingle();
      return APIResponse.success({'message': row});
    } catch (e) {
      return APIResponse.error(e);
    }
  }

  Future<void> unsubscribe(RealtimeChannel channel) async {
    try {
      await _client.removeChannel(channel);
    } catch (_) {}
  }
}
