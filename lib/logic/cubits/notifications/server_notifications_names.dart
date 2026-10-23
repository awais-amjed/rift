part of 'server_notifications_cubit.dart';

/// Turning a sender id into a name, for servers the user isn't looking at.
///
/// A direct message from a background server arrives here as a row of
/// ciphertext: the body is unreadable without that conversation's key, which
/// only [DmCubit] holds and only for the selected server. So the most this tier
/// can honestly say is *who* sent it — and even that takes a lookup, because
/// [Server] carries its channels but not its members.
///
/// The lookup is worth the round trip: "Noor sent you a message" is actionable
/// and "New direct message" is barely more than the badge already showing. It
/// happens once per sender per session — names are cached, including the misses,
/// so a peer whose row can't be read (banned, deleted, RLS) doesn't cost a query
/// on every message they send.
mixin _PeerNamesMixin on Cubit<NotificationsState> {
  SessionRepository get _session;
  Map<String, _ServerSub> get _subs;

  /// `serverId:userId` → display name, or null for a lookup that came back
  /// empty. Present-but-null is the "don't ask again" marker, which is why this
  /// holds `String?` rather than being a plain `Map<String, String>`.
  final Map<String, String?> _peerNames = {};

  /// Drop a server's cached names when its subscription goes away, so a rejoin
  /// under a different identity doesn't inherit the last one's directory.
  void _forgetPeerNames(String serverId) {
    _peerNames.removeWhere((key, _) => key.startsWith('$serverId:'));
  }

  Future<String?> _peerDisplayName(String serverId, String userId) async {
    final key = '$serverId:$userId';
    if (_peerNames.containsKey(key)) return _peerNames[key];

    if (!_subs.containsKey(serverId)) return null;

    // A failed lookup is cached as a miss like any other: the notification
    // still goes out unnamed, and retrying per message would turn one
    // unreachable server into a query storm.
    final member = await MembersApi(_session.on(serverId)).findMember(userId);
    final name = member == null
        ? null
        : member.displayName.isNotEmpty
        ? member.displayName
        : member.username;

    if (isClosed) return name;
    _peerNames[key] = name;
    return name;
  }
}
