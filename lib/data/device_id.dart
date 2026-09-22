import 'dart:math';

/// A per-run device id, mixed into LiveKit participant identities so the same
/// user can be connected from several devices without the later connection
/// kicking the earlier one.
///
/// It only has to hold for one run — long enough for a call and its shares to
/// carry the same one, which is how a share is told to be this device's — so
/// it is in memory and regenerated each launch; per-user state persists under
/// the user id, not the identity. Anything that outlives a run and holds an
/// identity, like a cached token, has to record which run it is from.
class DeviceId {
  const DeviceId._();

  static final String current = _generate();

  static String _generate() {
    final random = Random();
    return List.generate(8, (_) => random.nextInt(16).toRadixString(16)).join();
  }
}
