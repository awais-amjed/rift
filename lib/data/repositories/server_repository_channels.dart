part of 'server_repository.dart';

/// Creating, renaming, deleting and closing channels on a self-hosted server.
///
/// All direct table calls except the two that cannot be. `set_channel_members`
/// and `set_channel_private` are RPCs because each does something an UPDATE
/// cannot: the first replaces a membership in one statement, so there is no
/// moment where a channel is private and everybody is still in it; the second
/// leaves a rotation marker behind, because opening a room must not hand its
/// private history to the next person who joins the server (ARCHITECTURE.md
/// §4, migration 020).
///
/// `is_private` has no column grant at all, which is what makes that second one
/// the only way in rather than the polite way in.
mixin _ChannelApiMixin {
  ServerDb get _db;

  /// Deleting one is the exception: it has to drop the LiveKit room too, and
  /// only something holding the API secret can. Implemented by the hub.
  Future<APIResponse> _post(
    String supabaseUrl,
    String functionName,
    Map<String, dynamic> body, {
    String? bearerToken,
  });

  /// Create a channel, and seat its members if it is private.
  ///
  /// An RPC rather than an insert, and not for the usual reason. `INSERT ...
  /// RETURNING` applies the *select* policy to the row it hands back, and a
  /// private channel's select policy asks whether the caller is in it — which
  /// they are not until the after-insert trigger seats them, which has not run
  /// yet. The insert succeeded and reading its own row did not (migration 022).
  ///
  /// Doing it in one statement also removes the mistake the two-call version
  /// was one forgotten id away from: `set_channel_members` replaces a
  /// membership with exactly what it is handed, and a private channel that
  /// loses its last member is deleted.
  Future<APIResponse> createChannel(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String name,
    required String channelType,
    bool isPrivate = false,
    List<String> memberIds = const [],
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      return db.rpc(
        'create_channel',
        params: {
          'p_name': name,
          'p_type': channelType,
          'p_private': isPrivate,
          'p_members': memberIds,
        },
      );
    });
  }

  /// Replace a private channel's membership with exactly [userIds].
  ///
  /// One call rather than add-then-remove: doing it in two leaves a window
  /// where the channel is private and everybody is still in it.
  Future<APIResponse> setChannelMembers(
    String supabaseUrl,
    String channelId, {
    required String anonKey,
    String? bearerToken,
    required List<String> userIds,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      return db.rpc(
        'set_channel_members',
        params: {'p_channel': channelId, 'p_users': userIds},
      );
    });
  }

  /// Open or close a channel.
  ///
  /// An RPC rather than an UPDATE because opening one has to leave a rotation
  /// behind it: the current key is the one the private conversation was written
  /// under, and anybody joining later must not be handed it.
  Future<APIResponse> setChannelPrivate(
    String supabaseUrl,
    String channelId, {
    required String anonKey,
    String? bearerToken,
    required bool isPrivate,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      return db.rpc(
        'set_channel_private',
        params: {'p_channel': channelId, 'p_private': isPrivate},
      );
    });
  }

  /// Remove yourself from a private channel.
  ///
  /// Its own function rather than a `set_channel_members` with one name
  /// missing: that one needs the manage bit, which is the right answer for who
  /// *else* is in a room and the wrong one for whether you are. This takes no
  /// target, which is what makes it safe for every member to hold.
  Future<APIResponse> leaveChannel(
    String supabaseUrl,
    String channelId, {
    required String anonKey,
    String? bearerToken,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      return db.rpc('leave_channel', params: {'p_channel': channelId});
    });
  }

  /// Who is in a private channel. Empty for a public one, and for a private one
  /// the caller is not in — which are indistinguishable on purpose.
  Future<APIResponse> listChannelMembers(
    String supabaseUrl,
    String channelId, {
    required String anonKey,
    String? bearerToken,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      final rows = await db
          .from('channel_members')
          .select('user_id, can_manage')
          .eq('channel_id', channelId);
      return {'members': rows};
    });
  }

  /// Server members a message in this channel can actually reach.
  ///
  /// An RPC rather than three selects the client stitches together: the answer
  /// is `app.channel_eligible`, which is also what strips a mention on the way
  /// in, and a Dart copy of it would have to read `channel_members`, read
  /// `channel_role_access`, resolve those through `member_roles` and remember
  /// the ban clause — four things to keep in step with one predicate. Migration
  /// 034.
  Future<APIResponse> listChannelAudience(
    String supabaseUrl,
    String channelId, {
    required String anonKey,
    String? bearerToken,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      final rows = await db.rpc(
        'channel_audience',
        params: {'p_channel': channelId},
      );
      return {'audience': rows};
    });
  }

  /// Update a channel's settings (requires channel manager).
  ///
  /// A plain update — the column grant covers only `name`, `retention_days`
  /// and `history_cap`, and `channels_update_managers` decides who may.
  /// Nothing else has to happen: a LiveKit room is named by the channel's
  /// **id**, so renaming a voice channel doesn't touch the call inside it.
  ///
  /// The retention overrides are three-valued, which is why they aren't plain
  /// `int?`s: omitted leaves the column alone, a value sets it, and the
  /// matching `clear…` flag writes NULL to go back to inheriting the server's.
  Future<APIResponse> updateChannel(
    String supabaseUrl,
    String channelId, {
    required String anonKey,
    String? bearerToken,
    String? name,
    int? retentionDays,
    bool clearRetentionDays = false,
    int? historyCap,
    bool clearHistoryCap = false,
  }) {
    return ServerDb.run(() async {
      final patch = <String, dynamic>{
        'name': ?name,
        if (clearRetentionDays)
          'retention_days': null
        else
          'retention_days': ?retentionDays,
        if (clearHistoryCap)
          'history_cap': null
        else
          'history_cap': ?historyCap,
      };
      if (patch.isEmpty) {
        throw const PostgrestException(message: 'Nothing to update');
      }
      final rows = await _db
          .client(supabaseUrl, anonKey, bearerToken)
          .from('channels')
          .update(patch)
          .eq('id', channelId)
          .select(
            'id, name, channel_type, retention_days, history_cap, is_private',
          );
      if ((rows as List).isEmpty) {
        throw const PostgrestException(
          message: 'Channel not found, or not yours to change',
        );
      }
      return rows.first;
    });
  }

  /// Delete a channel (requires channel manager), and the call inside it.
  ///
  /// An edge function rather than a table delete, because the row is only half
  /// of it: the LiveKit room is named by the channel id, and dropping that room
  /// is what disconnects everyone still talking in it. The function does the
  /// delete with this same JWT, so the policy is still what decides.
  Future<APIResponse> deleteChannel(
    String supabaseUrl,
    String channelId, {
    String? bearerToken,
  }) {
    return _post(supabaseUrl, 'delete_channel', {
      'channel_id': channelId,
    }, bearerToken: bearerToken);
  }

  /// Persistently mute/unmute/deafen/undeafen a user (server admin). State is
  /// stored server-side and enforced in LiveKit token grants, so it survives
  /// rejoins and can't be self-reverted.
  ///
  /// An RPC rather than an update: RLS is row-level, so a policy that let an
  /// admin write another member's moderation flags would let them write that
  /// member's identity too.
  /// Mute / deafen / ban a member (admin only).
  ///
  /// An edge function rather than the `moderate_user` RPC directly, because the
  /// row write is only half the job: the other half is pushing the new state
  /// onto the target's live LiveKit connections, which needs the API secret.
  /// The function still calls that same RPC with the caller's JWT, so the
  /// permission rules stay in the database.
  Future<APIResponse> moderateUser(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String userId,
    bool? isMuted,
    bool? isDeafened,
    bool? isBanned,
  }) {
    return _post(supabaseUrl, 'moderate_user', {
      'target_user_id': userId,
      'muted': isMuted,
      'deafened': isDeafened,
      'banned': isBanned,
    }, bearerToken: bearerToken);
  }
}
