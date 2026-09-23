import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../../data/repositories/soundboard_repository.dart';
import 'byte_format.dart';
import 'soundboard_play.dart';

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

  /// Why a clip that plays for [duration] cannot be added, or null.
  ///
  /// Asked after [measure], because the length is not in the file's name or
  /// its size. A refusal rather than a warning: "the first 30 seconds of
  /// this will play" is almost never what somebody meant by uploading a
  /// four-minute track, and telling them the real length is more use than
  /// silently keeping a third of it.
  ///
  /// [Duration.zero] passes. It means no backend would say how long the file
  /// is, not that it is empty — and refusing on an answer nobody could get
  /// would make a clip's acceptance depend on which platform added it.
  /// [SoundboardPlay.maxPlayback] is what catches that one, at play time.
  static String? rejectionForDuration({
    required String fileName,
    required Duration duration,
  }) {
    if (duration <= Duration.zero) return null;
    if (duration <= SoundboardPlay.maxPlayback) return null;
    return '$fileName is ${durationLabel(duration)} — a clip can be up to '
        '${durationLabel(SoundboardPlay.maxPlayback)}. Trim it first.';
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

  /// How long the picked file plays for, measured by the same audio stack
  /// that will play it, or [Duration.zero] when it will not say.
  ///
  /// Both the label and the check: [rejectionForDuration] reads it, and the
  /// row stores it. Neither is authoritative — the server cannot verify a
  /// number the client measured, and a file no backend will measure comes
  /// back as zero — so [SoundboardPlay.maxPlayback] stays the bound that
  /// cannot be talked past.
  ///
  /// From [path] where there is one, and only from [bytes] on the web.
  /// `BytesSource` is not implemented by the Linux or Windows audioplayers
  /// backends, so measuring from memory on a desktop answers nothing at all
  /// — every clip added from one read "—" until this took the file instead.
  static Future<Duration> measure(Uint8List bytes, {String? path}) async {
    final player = AudioPlayer();
    try {
      await player.setSource(
        path == null || kIsWeb ? BytesSource(bytes) : DeviceFileSource(path),
      );
      // Played silently to get the answer. `getDuration` reads the platform
      // player's idea of the length, and on Linux that is a GStreamer
      // pipeline which stays in NULL until something asks it to run — so
      // after `setSource` alone it answers null forever, however long you
      // wait, and every clip added from a desktop was labelled "—".
      //
      // Muted first, and only then started: this runs while somebody is
      // filling in a form, and a burst of airhorn out of the speakers is not
      // what they asked for.
      await player.setVolume(0);
      await player.resume();

      // Polled, because the length arrives with the pipeline rather than
      // with the call. Bounded, because for some files it never arrives and
      // a form that waits forever on a label is worse than a missing label.
      for (var attempt = 0; attempt < 16; attempt++) {
        final measured = await player.getDuration();
        if (measured != null && measured > Duration.zero) {
          await player.stop();
          return measured;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      await player.stop();
      return Duration.zero;
    } catch (_) {
      return Duration.zero;
    } finally {
      unawaited(player.dispose().catchError((_) {}));
    }
  }

  /// `1.2 s`, or an em dash for a length nobody could measure.
  static String durationLabel(Duration duration) {
    if (duration <= Duration.zero) return '—';
    // A whole number of seconds drops its decimal, the way [humanSize] does:
    // the cap this labels is 30 seconds, and "30.0 s" reads as a measurement
    // rather than as the rule it is.
    final text = (duration.inMilliseconds / 1000).toStringAsFixed(1);
    return '${text.endsWith('.0') ? text.substring(0, text.length - 2) : text} s';
  }
}
