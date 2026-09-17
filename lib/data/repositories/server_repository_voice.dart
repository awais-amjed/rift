part of 'server_repository.dart';

/// Joining a call, and the three things a moderator does to one.
///
/// Every one of these holds the LiveKit API secret at some point, which is why
/// none of them is a table call: minting a token, moving somebody between
/// rooms, and removing them are all things only the server may do. Attachment
/// sweeping is here for a different reason — it needs the Storage API, which no
/// database role can reach.
mixin _VoiceApiMixin {
  Future<APIResponse> _post(
    String supabaseUrl,
    String functionName,
    Map<String, dynamic> body, {
    String? bearerToken,
  });

  /// A stable per-run device id, mixed into LiveKit participant identities so
  /// the same user can be connected from multiple devices without the later
  /// connection kicking the earlier one.
  ///
  /// It only has to be consistent within a single app run — long enough for a
  /// voice session and its screen-share to share it — so an in-memory value,
  /// regenerated each launch, is enough; per-user state persists under the user
  /// id, not the identity.
  static final String _deviceId = _generateDeviceId();

  static String _generateDeviceId() {
    final random = Random();
    return List.generate(8, (_) => random.nextInt(16).toRadixString(16)).join();
  }

  /// Get a LiveKit JWT for joining a channel.
  ///
  /// [screenShare] and [soundShare] each ask for the identity of that kind of
  /// share instead of the caller's own — a share is a second connection, and
  /// the two kinds have suffixes of their own so one member can run both at
  /// once without their connections kicking each other.
  Future<APIResponse> getChannelToken(
    String supabaseUrl,
    String channelId, {
    bool screenShare = false,
    bool soundShare = false,
    String? bearerToken,
  }) {
    return _post(supabaseUrl, 'get_channel_token', {
      'channel_id': channelId,
      'screen_share': screenShare,
      'sound_share': soundShare,
      'device_id': _deviceId,
    }, bearerToken: bearerToken);
  }

  /// Apply the server's retention settings and remove the attachment blobs
  /// left behind (`002_limits.sql`).
  ///
  /// An edge function rather than a table call, and not for the usual reason:
  /// this one needs the *Storage API*. `storage.protect_delete()` refuses a
  /// direct DELETE on `storage.objects`, so no database role can free a blob —
  /// only something holding the service key can finish the job.
  Future<APIResponse> sweepAttachments(
    String supabaseUrl, {
    String? bearerToken,
  }) => _post(
    supabaseUrl,
    'sweep_attachments',
    const {},
    bearerToken: bearerToken,
  );

  /// Pull a member from the voice channel they're in into [channelId]
  /// (channel manager or admin).
  ///
  /// Nothing is written down — a move only exists as a live connection — so
  /// there is no table call to make. The function holds the LiveKit API secret
  /// and uses it to send the target's own connections a "join this channel"
  /// packet, which their client then does the ordinary way.
  Future<APIResponse> moveUser(
    String supabaseUrl, {
    String? bearerToken,
    required String userId,
    required String channelId,
  }) {
    return _post(supabaseUrl, 'move_user', {
      'target_user_id': userId,
      'channel_id': channelId,
    }, bearerToken: bearerToken);
  }

  /// Disconnect a member from the voice channel they're in (channel manager
  /// or admin).
  ///
  /// The transient half of moderation: nothing is written down and they may
  /// rejoin immediately. Like [moveUser] it needs the LiveKit API secret, and
  /// like it there is no table call to make — the difference is that this ends
  /// every connection they hold here, screen share included.
  Future<APIResponse> kickUser(
    String supabaseUrl, {
    String? bearerToken,
    required String userId,
  }) {
    return _post(supabaseUrl, 'kick_user', {
      'target_user_id': userId,
    }, bearerToken: bearerToken);
  }

  /// Who is in which voice channel right now, as LiveKit sees it:
  /// `{roster: {userId: channelId}}`.
  ///
  /// The snapshot a client starts from before it can rely on hearing about
  /// changes — see [VoiceBroadcast].
  Future<APIResponse> voiceRoster(String supabaseUrl, {String? bearerToken}) {
    return _post(
      supabaseUrl,
      'voice_roster',
      const {},
      bearerToken: bearerToken,
    );
  }

  /// Ask a bot into a voice channel, or send it away (`010_bot_permissions.sql`).
  ///
  /// Not a key grant and not membership: it lets the bot take a token for this
  /// one channel and publish there. Hearing stays behind `MANAGE_BOTS`, so a
  /// summon adds a speaker to the room and never a listener.
  ///
  /// An edge function rather than the RPC directly, and only dismissing needs
  /// it: deleting the row takes away the bot's media key and its right to a
  /// *new* token, and does nothing to the connection it already holds, which is
  /// good for its hour. Without the push, "Send away" removed the row and left
  /// the bot in the call playing music. Same shape as `set_bot_voice_listen`.
  Future<APIResponse> setBotVoiceSummon(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String channelId,
    required String botId,
    required bool summon,
  }) {
    return _post(supabaseUrl, 'set_bot_voice_summon', {
      'bot_id': botId,
      'channel_id': channelId,
      'summon': summon,
    }, bearerToken: bearerToken);
  }
}
