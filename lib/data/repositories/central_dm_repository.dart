import 'package:supabase_flutter/supabase_flutter.dart';

import '../classes/api_response.dart';

/// Central-server DM I/O (Stage 3 — the discovery/first-contact tier,
/// ARCHITECTURE.md §4). Everything runs over the central Supabase client with
/// the user's GoTrue session: RLS scopes reads, and writes go through the
/// quota-enforcing `send_dm` RPC. Content is E2E — this repository only moves
/// opaque envelopes and directory rows.
class CentralDmRepository {
  SupabaseClient get _client => Supabase.instance.client;

  User? get currentUser => _client.auth.currentUser;

  Stream<AuthState> get authChanges => _client.auth.onAuthStateChange;

  // ──────────────────────────────────────────────────────────
  // Directory (dm_profiles)
  // ──────────────────────────────────────────────────────────

  /// The caller's own directory row, or success(null) when not created yet.
  Future<APIResponse> getMyProfile() async {
    try {
      final row = await _client
          .from('dm_profiles')
          .select()
          .eq('user_id', _client.auth.currentUser!.id)
          .maybeSingle();
      return APIResponse.success(row);
    } catch (e) {
      return APIResponse.error(e);
    }
  }

  /// Create or refresh the caller's directory row. Fails with a unique
  /// violation when the handle is taken by someone else.
  Future<APIResponse> upsertProfile({
    required String handle,
    required String chatPublicKey,
    required String signingPublicKey,
  }) async {
    try {
      await _client.from('dm_profiles').upsert({
        'user_id': _client.auth.currentUser!.id,
        'handle': handle,
        'chat_public_key': chatPublicKey,
        'signing_public_key': signingPublicKey,
      }, onConflict: 'user_id');
      return APIResponse.success(null);
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        return APIResponse(
          success: false,
          error: 'That handle is already taken',
          errorCode: 'handle_taken',
        );
      }
      return APIResponse.error(e.message);
    } catch (e) {
      return APIResponse.error(e);
    }
  }

  /// Prefix-search the directory (excluding the caller).
  Future<APIResponse> searchHandles(String prefix) async {
    try {
      final rows = await _client
          .from('dm_profiles')
          .select()
          .ilike('handle', '$prefix%')
          .neq('user_id', _client.auth.currentUser!.id)
          .order('handle', ascending: true)
          .limit(10);
      return APIResponse.success(rows);
    } catch (e) {
      return APIResponse.error(e);
    }
  }

  /// Fetch directory rows for a set of user ids.
  Future<APIResponse> getProfiles(List<String> userIds) async {
    try {
      final rows = await _client
          .from('dm_profiles')
          .select()
          .inFilter('user_id', userIds);
      return APIResponse.success(rows);
    } catch (e) {
      return APIResponse.error(e);
    }
  }

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
      final result = await _client.rpc('send_dm', params: {
        'recipient': recipientId,
        'ciphertext': envelope['ciphertext'],
        'nonce': envelope['nonce'],
        'signature': envelope['signature'],
        'key_version': envelope['key_version'],
      });
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

  /// Page through the conversation with [peerId] (RLS already restricts rows
  /// to the caller's own conversations).
  Future<APIResponse> listDms({
    required String peerId,
    int? beforeId,
    int? afterId,
    int limit = 50,
  }) async {
    try {
      final myId = _client.auth.currentUser!.id;
      var query = _client.from('dm_messages').select().or(
            'and(sender_id.eq.$myId,recipient_id.eq.$peerId),'
            'and(sender_id.eq.$peerId,recipient_id.eq.$myId)',
          );
      if (afterId != null) query = query.gt('id', afterId);
      if (beforeId != null) query = query.lt('id', beforeId);
      final rows = await query
          .order('id', ascending: afterId != null)
          .limit(limit);
      return APIResponse.success(rows);
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
