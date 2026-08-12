import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../logic/services/chat_message_ops.dart';
import '../classes/api_response.dart';
import 'attachment_repository.dart';

part 'central_dm_repository_attachments.dart';
part 'central_dm_repository_directory.dart';
part 'central_dm_repository_read_state.dart';

/// Central-server DM I/O (Stage 3 — the discovery/first-contact tier,
/// ARCHITECTURE.md §4). Everything runs over the central Supabase client with
/// the user's GoTrue session: RLS scopes reads, and writes go through the
/// quota-enforcing `send_dm` RPC. Content is E2E — this repository only moves
/// opaque envelopes and directory rows.
class CentralDmRepository
    with
        _CentralDmAttachmentsMixin,
        _CentralDmDirectoryMixin,
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
  /// `{id, created_at, remaining, quota}`; quota exhaustion surfaces as
  /// errorCode `quota_exceeded`.
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
      final known = [
        'quota_exceeded',
        'recipient_has_no_profile',
        'sender_has_no_profile',
        'cannot_dm_self',
        'envelope_invalid',
      ].firstWhere((code) => e.message.contains(code), orElse: () => '');
      return APIResponse(
        success: false,
        error: known.isNotEmpty ? known : e.message,
        errorCode: known.isNotEmpty ? known : null,
      );
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
      // One row past the page — see ChatMessageOps.splitPage.
      final rows = await query
          .order('id', ascending: afterId != null)
          .limit(limit + 1);
      final page = ChatMessageOps.splitPage(
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

  /// Recent envelopes involving the caller (newest first) — the cubit groups
  /// them into conversations.
  Future<APIResponse> listRecentMessages({int limit = 1000}) async {
    try {
      final myId = _client.auth.currentUser!.id;
      final rows = await _client
          .from('dm_messages')
          .select()
          .or('sender_id.eq.$myId,recipient_id.eq.$myId')
          .order('id', ascending: false)
          .limit(limit);
      return APIResponse.success(rows);
    } catch (e) {
      return APIResponse.error(e);
    }
  }

  // ──────────────────────────────────────────────────────────
  // Realtime
  // ──────────────────────────────────────────────────────────

  /// Subscribe to incoming DMs (INSERTs addressed to the caller). Returns the
  /// channel so the caller can unsubscribe.
  RealtimeChannel subscribeIncoming(void Function() onInsert) {
    final myId = _client.auth.currentUser!.id;
    final channel = _client.channel('central-dm-incoming')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'dm_messages',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'recipient_id',
          value: myId,
        ),
        callback: (_) => onInsert(),
      )
      ..subscribe();
    return channel;
  }

  Future<void> unsubscribe(RealtimeChannel channel) async {
    try {
      await _client.removeChannel(channel);
    } catch (_) {}
  }
}
