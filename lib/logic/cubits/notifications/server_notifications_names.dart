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

    final sub = _subs[serverId];
    if (sub == null) return null;

    String? name;
    try {
      final row = await sub.client
          .from('users')
          .select('display_name, username')
          .eq('id', userId)
          .maybeSingle();
      if (row != null) {
        final display = row['display_name'] as String?;
        final username = row['username'] as String?;
        name = (display != null && display.isNotEmpty) ? display : username;
      }
    } catch (_) {
      // A failed lookup is cached as a miss like any other: the notification
      // still goes out unnamed, and retrying per message would turn one
      // unreachable server into a query storm.
    }

    if (isClosed) return name;
    _peerNames[key] = name;
    return name;
  }
}
