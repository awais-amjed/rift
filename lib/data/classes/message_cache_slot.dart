/// Which conversation a saved copy belongs to.
///
/// Two halves because the copies are wiped at two sizes: a whole [scope] when
/// the device leaves a server or signs out of central, one [conversation] when
/// only that one is lost — a channel the server stops listing. Neither half is ever written to the disk as it is —
/// both are run through an HMAC first, so the file names do not say which
/// servers or people this device talks to.
class MessageCacheSlot {
  /// The server, or central.
  final String scope;

  /// The channel or the peer, within [scope].
  final String conversation;

  const MessageCacheSlot._(this.scope, this.conversation);

  /// A server's text channel. Keyed by the server's address *and* id, because
  /// several servers can share one project (see `Server`).
  MessageCacheSlot.channel({
    required String supabaseUrl,
    required String serverId,
    required String channelId,
  }) : this._(serverScope(supabaseUrl, serverId), 'channel:$channelId');

  /// A direct message on a server.
  MessageCacheSlot.serverDm({
    required String supabaseUrl,
    required String serverId,
    required String peerId,
  }) : this._(serverDmScope(supabaseUrl, serverId), 'dm:$peerId');

  /// A direct message through central.
  MessageCacheSlot.centralDm({required String peerId})
    : this._(centralScope, 'dm:$peerId');

  /// A server's channels. Apart from its DMs so that the channels can be
  /// pruned to the ones the server still lists without touching a DM.
  static String serverScope(String supabaseUrl, String serverId) =>
      'server:$supabaseUrl:$serverId';

  /// A server's DMs.
  static String serverDmScope(String supabaseUrl, String serverId) =>
      'server-dm:$supabaseUrl:$serverId';

  /// Everything saved for one server — what leaving it takes away.
  static List<String> scopesOfServer(String supabaseUrl, String serverId) => [
    serverScope(supabaseUrl, serverId),
    serverDmScope(supabaseUrl, serverId),
  ];

  /// Every central conversation.
  static const String centralScope = 'central';

  /// What the sealed file says it is, so a file moved onto another's name
  /// opens as the wrong conversation and is refused.
  String get label => '$scope|$conversation';

  @override
  bool operator ==(Object other) =>
      other is MessageCacheSlot &&
      other.scope == scope &&
      other.conversation == conversation;

  @override
  int get hashCode => Object.hash(scope, conversation);
}
