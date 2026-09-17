/// The state a client publishes about itself into a call.
///
/// LiveKit tells the room about tracks, not about intentions. A muted
/// microphone is visible because the track goes away; deafening is a decision
/// made entirely inside the listener's client — it unsubscribes from other
/// people's audio, which nobody else can see. So it is said out loud, as a
/// participant attribute, and everyone's roster can show it.
///
/// Attributes are plain strings, and an attribute that has never been set is
/// simply absent — so reading is written to accept anything and answer no.
class VoiceAttributes {
  const VoiceAttributes._();

  static const deafenedKey = 'deafened';

  /// What to publish for a client that is (or is not) deafened.
  static Map<String, String> forSelf({required bool deafened}) => {
    deafenedKey: deafened ? 'true' : 'false',
  };

  static bool isDeafened(Map<String, String> attributes) =>
      attributes[deafenedKey] == 'true';
}
