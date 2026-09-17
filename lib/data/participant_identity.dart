/// Helpers for the LiveKit participant identity scheme.
///
/// Identity format: `<userId>~<deviceId>` for a normal participant, with a
/// `_screenshare` or `_soundshare` suffix for that same device's screen share
/// or sound share — e.g. `d290f1ee-…~a1b2c3d4` and
/// `d290f1ee-…~a1b2c3d4_screenshare`.
///
/// The device segment lets one user join from several devices without a
/// LiveKit identity collision (a duplicate identity kicks the earlier
/// connection). The two shares have suffixes of their own for that same
/// reason: somebody sharing a screen and a track at once is two extra
/// connections, not one fighting itself.
///
/// The user id is always the part before the first `~`, so per-user concerns —
/// moderation, local mute/volume, de-duplication — key off [userIdOf] rather
/// than the raw identity.
class ParticipantIdentity {
  const ParticipantIdentity._();

  static const screenshareSuffix = '_screenshare';
  static const soundShareSuffix = '_soundshare';

  static bool isScreenshare(String identity) =>
      identity.endsWith(screenshareSuffix);

  /// Whether this connection is somebody sharing an application's sound.
  static bool isSoundShare(String identity) =>
      identity.endsWith(soundShareSuffix);

  /// Whether this connection is a share of either kind — a second connection
  /// held by somebody already in the call, rather than a person.
  static bool isShare(String identity) =>
      isScreenshare(identity) || isSoundShare(identity);

  /// The base (non-share) identity — `<userId>~<deviceId>`. A share's identity
  /// maps to its owner's base identity by dropping the suffix, which is how a
  /// share is paired with the connection that started it.
  static String baseOf(String identity) {
    for (final suffix in const [screenshareSuffix, soundShareSuffix]) {
      if (identity.endsWith(suffix)) {
        return identity.substring(0, identity.length - suffix.length);
      }
    }
    return identity;
  }

  /// Whether [identity] is a share started by the connection [localIdentity].
  ///
  /// Matched on the base identity rather than the user id: a share belongs to
  /// the device that started it. Somebody sharing music from their desktop
  /// should still hear it on the phone they are also in the call from, where
  /// nothing is playing out of the speakers in front of them.
  static bool isShareOf(String identity, String? localIdentity) =>
      localIdentity != null &&
      isShare(identity) &&
      baseOf(identity) == localIdentity;

  /// The key a sound share's local mute and volume are stored under.
  ///
  /// Not the raw identity, which carries a device segment regenerated every
  /// launch, and not the plain user id either: turning down somebody's music
  /// should not turn down their voice.
  static String soundShareSettingsKey(String identity) =>
      '${userIdOf(identity)}$soundShareSuffix';

  /// The user id encoded in an identity, independent of device or share.
  /// Falls back to the whole base string for legacy identities issued before
  /// the device segment existed (no `~`).
  static String userIdOf(String identity) {
    final base = baseOf(identity);
    final sep = base.indexOf('~');
    return sep < 0 ? base : base.substring(0, sep);
  }

  /// Whether [identity] is one of [userId]'s voice connections — any device
  /// they've joined from, but neither of their shares, whose audio is handled
  /// separately.
  ///
  /// This is the rule for anything that should reach *the person*: applying a
  /// local mute has to hit every device they're on, not the one connection
  /// whose identity happened to be at hand.
  static bool isVoiceConnectionOf(String identity, String userId) =>
      !isShare(identity) && userIdOf(identity) == userId;
}
