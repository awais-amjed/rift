import 'package:livekit_client/livekit_client.dart';

import '../../data/participant_identity.dart';

/// Who in a call may receive your microphone, for "Hide my voice from them"
/// and "Hide my voice from others".
///
/// The call server enforces it: your app tells LiveKit which participants may
/// subscribe to which of your tracks, and the server sends nothing to the
/// rest. Their app is never asked to look away, so a modified one hears no
/// more than a stock one.
///
/// LiveKit has no "everyone but these" — allowing everyone overrides any
/// list. So once anybody is hidden, the call runs on an allow-list instead:
/// everyone present is named, a hidden person with every track but the mic.
/// Somebody who joins after you is allowed the moment this device hears of
/// them, and hears nothing of you until then, which is the safe way round.
/// So is a track published after the list was sent: it reaches a hidden
/// person only once the list is sent again and names it, and the list never
/// names a microphone.
abstract final class VoicePrivacy {
  /// The permissions to send for a call with [remoteIdentities] in it.
  ///
  /// [hiddenFrom] holds user ids, so every connection of theirs is covered:
  /// each device, and their shares, whose connections could subscribe too.
  /// [nonMicTrackSids] are the tracks of yours a hidden person still gets —
  /// a camera, or a phone's screen share.
  ///
  /// [onlyTo], a user id, hides it from everyone else as well. Somebody in
  /// [hiddenFrom] stays hidden even then.
  static ({bool allowAll, List<ParticipantTrackPermission> permissions})
  permissions({
    required Iterable<String> remoteIdentities,
    required Iterable<String> hiddenFrom,
    required Iterable<String> nonMicTrackSids,
    String? onlyTo,
  }) {
    final hidden = hiddenFrom.toSet();
    if (hidden.isEmpty && onlyTo == null) {
      return (allowAll: true, permissions: const []);
    }
    bool isHidden(String userId) =>
        hidden.contains(userId) || (onlyTo != null && userId != onlyTo);
    final others = nonMicTrackSids.toList();
    return (
      allowAll: false,
      permissions: [
        for (final identity in remoteIdentities)
          if (isHidden(ParticipantIdentity.userIdOf(identity)))
            ParticipantTrackPermission(identity, false, others)
          else
            ParticipantTrackPermission(identity, true, null),
      ],
    );
  }
}
