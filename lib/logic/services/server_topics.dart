/// The Realtime topics a self-hosted server speaks on, and what is said there.
///
/// Every one is private (migration 017's `app.can_use_topic` decides who may
/// join), and most of what is said comes from the database itself, not from
/// another client — the names below are the other half of that migration's
/// triggers, and have to match them exactly.
class ServerTopics {
  const ServerTopics._();

  /// Every member of the server.
  static String server(String serverId) => 'server:$serverId';

  /// One person: their DMs, their private channels' messages, what is
  /// addressed to them alone. Only they may join it; any co-member may ring it.
  static String user(String userId) => 'user:$userId';

  /// One channel's typing indicators, for whoever can see the channel.
  static String chat(String channelId) => 'chat:$channelId';

  /// What the database says about one **private** channel, for whoever can
  /// see it (migration 027).
  ///
  /// An open channel's news goes to [server]; a private one cannot, because
  /// that topic is the whole membership. It used to be sent to each member's
  /// own topic instead — one row in `realtime.messages` per person who could
  /// see the channel, written by the transaction that sent the message, which
  /// measured 176 ms for a channel 8,750 people could read. Now it is one row
  /// and Realtime does the fanning out, as it already did for open channels.
  ///
  /// Listen-only, unlike every other topic here: [chat] is where a client
  /// says something about a channel, and this is where the database does.
  /// Keeping them apart is what stops a member forging a `message` event to
  /// everyone in a private channel.
  static String channel(String channelId) => 'channel:$channelId';

  /// Who is online. See `ChannelPresenceCubit`.
  static String presence(String serverId) => 'presence:$serverId';
}

/// What is said on those topics.
class ServerEvent {
  const ServerEvent._();

  // From the database, on the server topic (open channels), a channel topic
  // (private channels) or a user topic (ephemeral replies).
  static const String message = 'message';
  static const String messageChanged = 'message_changed';
  static const String reaction = 'reaction';

  // From the database, on the server topic.
  static const String channels = 'channels';
  static const String members = 'members';

  /// The soundboard library moved. Not a play — a play never reaches the
  /// database at all, and this is only "go and re-read the list".
  static const String soundboard = 'soundboard';

  // From the database, on a user topic.
  static const String me = 'me';
  static const String dm = 'dm';
  static const String dmChanged = 'dm_changed';
  static const String dmReaction = 'dm_reaction';
  static const String prefs = 'prefs';

  // From clients.
  static const String typing = 'typing';
  static const String changed = 'changed';
  static const String sweep = 'sweep';
}
