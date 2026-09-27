/// Which DM call a device is in: enough to name it on screen and to join its
/// room again after a dropped connection, and nothing about how it is going
/// — that is the call row's ([DmCall]), and the call cubit's to follow.
class DmCallPlace {
  final String serverId;
  final String callId;
  final String peerId;
  final String peerName;

  const DmCallPlace({
    required this.serverId,
    required this.callId,
    required this.peerId,
    required this.peerName,
  });

  @override
  bool operator ==(Object other) =>
      other is DmCallPlace &&
      other.serverId == serverId &&
      other.callId == callId &&
      other.peerId == peerId &&
      other.peerName == peerName;

  @override
  int get hashCode => Object.hash(serverId, callId, peerId, peerName);
}
