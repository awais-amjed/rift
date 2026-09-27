/// A notification id that is the same for the same thing on every run.
///
/// FNV-1a rather than [Object.hashCode], which Dart does not promise to keep
/// between runs — and a push wake is a new run every time. An id that moved
/// would stack a second notification instead of replacing, or fail to take
/// down, the one already in the shade.
int stableNotificationId(String scope) {
  var hash = 0x811c9dc5;
  for (final unit in scope.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
  }
  return hash;
}

/// The one notification a DM call has, whoever posts it — the push isolate
/// ringing it, or the app taking it down once the call is answered or over.
int callNotificationId(String callId) => stableNotificationId('call:$callId');

/// What a call notification carries, so a press on it knows which call on
/// which server it was: `dmcall|<serverId>|<callId>`.
class CallNotificationPayload {
  static const _tag = 'dmcall';

  final String serverId;
  final String callId;

  const CallNotificationPayload(this.serverId, this.callId);

  String encode() => '$_tag|$serverId|$callId';

  /// Null for anything that is not a call's payload.
  static CallNotificationPayload? decode(String? raw) {
    final parts = raw?.split('|');
    if (parts == null || parts.length != 3 || parts[0] != _tag) return null;
    if (parts[1].isEmpty || parts[2].isEmpty) return null;
    return CallNotificationPayload(parts[1], parts[2]);
  }
}
