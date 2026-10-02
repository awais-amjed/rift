part of 'server_repository.dart';

/// Reports, time-outs and blocks on a self-hosted server.
///
/// Filing a report is an RPC because the server copies the reported message's
/// sealed envelope itself — the reporter supplies which message and why, never
/// the bytes. Reading the list is a plain select: `reports_select` shows a
/// reviewer their server's rows and nobody else anything. Blocks are the
/// caller's own rows, read and written directly.
mixin _ModerationApiMixin {
  ServerDb get _db;

  // ── Reports ───────────────────────────────────────────────

  /// Report a channel message. Refused as `already_reported`,
  /// `cannot_report_self` or `too_many_reports`.
  Future<APIResponse> reportMessage(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required int messageId,
    required String reason,
    String? note,
  }) {
    return ServerDb.run(
      () => _db
          .client(supabaseUrl, anonKey, bearerToken)
          .rpc(
            'report_message',
            params: {
              'p_message': messageId,
              'p_reason': reason,
              'p_note': note,
            },
          ),
    );
  }

  /// Report a member — from a profile, or from a DM whose words no moderator
  /// could open.
  Future<APIResponse> reportMember(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String targetId,
    required String reason,
    String? note,
  }) {
    return ServerDb.run(
      () => _db
          .client(supabaseUrl, anonKey, bearerToken)
          .rpc(
            'report_member',
            params: {'p_target': targetId, 'p_reason': reason, 'p_note': note},
          ),
    );
  }

  /// A page of this server's reports, newest first — the open ones, or the
  /// closed ones kept for 90 days.
  Future<APIResponse> listReports(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required bool open,
    int limit = 50,
  }) {
    return ServerDb.run(() async {
      // Both people and the channel ride along, each under its own policy:
      // a private channel the reviewer is not inside comes back null, which
      // is what the page says about it.
      final query = _db
          .client(supabaseUrl, anonKey, bearerToken)
          .from('reports')
          .select(
            '*, '
            'reporter:users!reports_reporter_id_fkey'
            '(display_name, username, avatar_path), '
            'target:users!reports_target_id_fkey'
            '(display_name, username, avatar_path, public_key, is_banned, '
            'kicked_at, timed_out_until), '
            'channel:channels(name)',
          );
      final filtered = open
          ? query.isFilter('outcome', null)
          : query.not('outcome', 'is', null);
      return await filtered.order('id', ascending: false).limit(limit);
    });
  }

  /// Record what was done. The server checks it happened
  /// (`outcome_not_done`) and answers how many reports it closed.
  Future<APIResponse> resolveReport(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required int reportId,
    required String outcome,
  }) {
    return ServerDb.run(
      () => _db
          .client(supabaseUrl, anonKey, bearerToken)
          .rpc(
            'resolve_report',
            params: {'p_report': reportId, 'p_outcome': outcome},
          ),
    );
  }

  // ── Time-outs ─────────────────────────────────────────────

  /// Time a member out for [minutes]; 0 lifts it. Answers when it ends.
  Future<APIResponse> timeOutMember(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String targetId,
    required int minutes,
  }) {
    return ServerDb.run(
      () => _db
          .client(supabaseUrl, anonKey, bearerToken)
          .rpc(
            'time_out_member',
            params: {'p_target': targetId, 'p_minutes': minutes},
          ),
    );
  }

  // ── Blocks ────────────────────────────────────────────────

  /// The ids the caller has blocked on this server.
  Future<APIResponse> listBlocks(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
  }) {
    return ServerDb.run(() async {
      final rows = await _db
          .client(supabaseUrl, anonKey, bearerToken)
          .from('member_blocks')
          .select('blocked_id');
      return [
        for (final row in (rows as List).cast<Map<String, dynamic>>())
          row['blocked_id'] as String,
      ];
    });
  }

  Future<APIResponse> setBlocked(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String userId,
    required String peerId,
    required bool blocked,
  }) {
    return ServerDb.run(() async {
      final table = _db
          .client(supabaseUrl, anonKey, bearerToken)
          .from('member_blocks');
      if (blocked) {
        try {
          await table.insert({'blocker_id': userId, 'blocked_id': peerId});
        } on PostgrestException catch (e) {
          // Already blocked, from this device or another: the answer wanted.
          if (e.code != '23505') rethrow;
        }
      } else {
        await table.delete().eq('blocker_id', userId).eq('blocked_id', peerId);
      }
      return null;
    });
  }
}
