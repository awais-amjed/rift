import 'classes/server_member.dart';

/// Everybody this client has met, `serverId → userId → member`.
///
/// Its job changed when the roster stopped arriving whole: it used to save a
/// round trip on top of a list we already held, and it is now the only
/// in-memory record of somebody we have seen at all. Every member read warms
/// it, and a lookup by id answers from it before asking the server.
///
/// Keyed by server because a user id only means something on the server it
/// came from — and because listing another server's members would otherwise
/// evict the entries the chat surfaces are about to ask for.
class MemberCache {
  final Map<String, Map<String, ServerMember>> _byServer = {};

  /// [userId] on [serverId], if this client has met them.
  ServerMember? lookup(String serverId, String userId) =>
      _byServer[serverId]?[userId];

  /// Remember [members] against [serverId], and hand them back unchanged so a
  /// caller can wrap a fetch in it.
  List<ServerMember> remember(String serverId, List<ServerMember> members) {
    final met = _byServer.putIfAbsent(serverId, () => {});
    for (final member in members) {
      met[member.id] = member;
    }
    return members;
  }
}
