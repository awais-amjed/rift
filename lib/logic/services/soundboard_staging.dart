import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

import '../../data/repositories/soundboard_repository.dart';
import 'byte_format.dart';

/// Turning a picked file into a clip — or into the reason it cannot be one.
///
/// The rules rather than the pixels, so the panel does not hold them and they
/// can be tested without a file picker (CODE_STYLE §6).
class SoundboardStaging {
  const SoundboardStaging._();

  /// What the clip is called. Matches the database's own CHECK, so a name
  /// that gets past this is one the insert will take.
  static const int maxNameLength = 32;

  /// Formats every target can decode. Narrower than what the bucket would
  /// accept, and deliberately so: a clip that plays for the person who
  /// uploaded it and is silence for half the room is worse than a refusal.
  static const List<String> extensions = ['mp3', 'm4a', 'aac', 'wav', 'ogg'];

  static const Set<String> _mimes = {
    'audio/mpeg',
    'audio/mp3',
    'audio/mp4',
    'audio/aac',
    'audio/wav',
    'audio/x-wav',
    'audio/wave',
    'audio/ogg',
    'audio/opus',
  };

  /// Why [name] of [bytes] length cannot be a clip, or null if it can.
  ///
  /// Phrased as whole sentences because they are shown verbatim.
  static String? rejectionFor({
    required String fileName,
    required String mime,
    required int bytes,
  }) {
    if (!_mimes.contains(mime.toLowerCase())) {
      return '$fileName is not an audio file Rift can play everywhere. '
          'Use ${extensions.join(', ')}.';
    }
    if (bytes > SoundboardRepository.maxBytes) {
      return '$fileName is ${humanSize(bytes)} — a clip can be up to '
          '${humanSize(SoundboardRepository.maxBytes)}.';
    }
    return null;
  }

  /// Why [name] is not a usable label, or null.
  static String? rejectionForName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'Give the clip a name.';
    if (trimmed.length > maxNameLength) {
      return 'That name is too long — $maxNameLength characters at most.';
    }
    return null;
  }

  /// How long [bytes] plays for, measured by the same audio stack that will
  /// play it, or [Duration.zero] when it will not say.
  ///
  /// A convenience, not a check: the server stores whatever this returns and
  /// cannot verify it, and the thing that actually bounds a long clip is the
  /// listener's own cutoff. It is here so the list can say "1.2 s" without
  /// asking the uploader to type it.
  static Future<Duration> measure(Uint8List bytes) async {
    final player = AudioPlayer();
    try {
      await player.setSource(BytesSource(bytes));
      // `getDuration` answers null until the source has been read, and on
      // some platforms never — hence the race rather than an await that can
      // hang a dialog on a file it could not parse.
      final measured = await Future.any([
        player.getDuration(),
        Future<Duration?>.delayed(const Duration(seconds: 3), () => null),
      ]);
      return measured ?? Duration.zero;
    } catch (_) {
      return Duration.zero;
    } finally {
      unawaited(player.dispose().catchError((_) {}));
    }
  }

  /// `1.2 s`, or an em dash for a length nobody could measure.
  static String durationLabel(Duration duration) {
    if (duration <= Duration.zero) return '—';
    return '${(duration.inMilliseconds / 1000).toStringAsFixed(1)} s';
  }
}
