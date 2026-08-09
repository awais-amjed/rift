/// Helpers for the LiveKit participant identity scheme.
///
/// Identity format: `<userId>~<deviceId>` for a normal participant, with a
/// `_screenshare` suffix for that same device's screen-share connection —
/// e.g. `d290f1ee-…~a1b2c3d4` and `d290f1ee-…~a1b2c3d4_screenshare`.
///
/// The device segment lets one user join from several devices without a
/// LiveKit identity collision (a duplicate identity kicks the earlier
/// connection). The user id is always the part before the first `~`, so
/// per-user concerns — moderation, local mute/volume, de-duplication — key off
/// [userIdOf] rather than the raw identity.
class ParticipantIdentity {
  const ParticipantIdentity._();

  static const screenshareSuffix = '_screenshare';

  static bool isScreenshare(String identity) =>
      identity.endsWith(screenshareSuffix);

  /// The base (non-screenshare) identity — `<userId>~<deviceId>`. A
  /// screenshare identity maps to its owner's base identity by dropping the
  /// suffix, which is how a share is paired with its participant.
  static String baseOf(String identity) => isScreenshare(identity)
      ? identity.substring(0, identity.length - screenshareSuffix.length)
      : identity;

  /// The user id encoded in an identity, independent of device or screenshare.
  /// Falls back to the whole base string for legacy identities issued before
  /// the device segment existed (no `~`).
  static String userIdOf(String identity) {
    final base = baseOf(identity);
    final sep = base.indexOf('~');
    return sep < 0 ? base : base.substring(0, sep);
  }

  /// Whether [identity] is one of [userId]'s voice connections — any device
  /// they've joined from, but not their screenshare, whose audio is handled
  /// separately.
  ///
  /// This is the rule for anything that should reach *the person*: applying a
  /// local mute has to hit every device they're on, not the one connection
  /// whose identity happened to be at hand.
  static bool isVoiceConnectionOf(String identity, String userId) =>
      !isScreenshare(identity) && userIdOf(identity) == userId;
}
