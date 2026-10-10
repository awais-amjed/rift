import 'dart:io';
import 'dart:math';

/// This install's device id, mixed into LiveKit participant identities so the
/// same user can be connected from several devices without the later
/// connection kicking the earlier one.
///
/// Kept per profile on disk ([loadFrom]) rather than made fresh each launch.
/// A fresh one made a restarted app — after a crash, a kill, a forced quit —
/// join as a second device: LiveKit kept the dead connection until it timed
/// out, and everybody saw two of the same person in the call. Under the same
/// identity LiveKit drops the old connection the moment the new one joins.
///
/// The web keeps a fresh one per run: its tabs share storage, and two tabs
/// under one identity would keep knocking each other out of a call.
///
/// Anything that holds an identity, like a cached token, records which id it
/// was minted under.
class DeviceId {
  const DeviceId._();

  static String _current = _generate();

  static String get current => _current;

  /// What the server keeps of it: up to 16 letters and digits.
  static final _shape = RegExp(r'^[0-9a-f]{8}$');

  /// Use the id saved in [file], or save this run's there. Call once at
  /// startup, before anything mints a token. A file that cannot be read or
  /// written leaves this run's fresh one, which is the old behaviour.
  static Future<void> loadFrom(File file) async {
    try {
      if (await file.exists()) {
        final saved = (await file.readAsString()).trim();
        if (_shape.hasMatch(saved)) {
          _current = saved;
          return;
        }
      }
      await file.parent.create(recursive: true);
      await file.writeAsString(_current, flush: true);
    } on FileSystemException {
      // Stays per run.
    }
  }

  static String _generate() {
    final random = Random.secure();
    return List.generate(8, (_) => random.nextInt(16).toRadixString(16)).join();
  }
}
