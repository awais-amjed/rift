import '../../src/rust/api/screenshare/types.dart';

/// Somebody watching a share, as far as its codec goes.
typedef ShareWatcher = ({String name, Set<VideoCodec> plays});

/// Which codec a desktop share goes out in, given who is watching it.
///
/// One stream, never a second encode: a weak computer cannot afford two. So a
/// watcher who cannot play what is being sent brings the whole share down to
/// something everyone watching can play (`CALLS.md`, "Stepping a share down").
/// Pure, so the rule can be read and tested in one place.
class ShareLadder {
  const ShareLadder._();

  /// Best first. VP8 is the floor: every WebRTC viewer has to play it.
  static const rungs = [
    VideoCodec.h265,
    VideoCodec.h264,
    VideoCodec.vp9,
    VideoCodec.vp8,
  ];

  /// The best rung at or below [top] that all of [watchers] play. [top] is
  /// what the sharer picked or Auto chose, or less once the GPU has failed.
  static VideoCodec rungFor({
    required VideoCodec top,
    required Iterable<ShareWatcher> watchers,
  }) {
    for (final rung in rungs.skip(rungs.indexOf(top))) {
      if (watchers.every((w) => w.plays.contains(rung))) return rung;
    }
    return rungs.last;
  }

  /// Whether [rung] is further down the ladder than [than].
  static bool isBelow(VideoCodec rung, VideoCodec than) =>
      rungs.indexOf(rung) > rungs.indexOf(than);

  /// The names of those holding the share at [rung]: who could not play the
  /// rung above it.
  static List<String> holdingAt(
    VideoCodec rung,
    Iterable<ShareWatcher> watchers,
  ) {
    final index = rungs.indexOf(rung);
    if (index == 0) return const [];
    final above = rungs[index - 1];
    return [
      for (final watcher in watchers)
        if (!watcher.plays.contains(above)) watcher.name,
    ];
  }

  /// [names] as the end of "so … can watch".
  static String whoFor(List<String> names) => switch (names) {
    [] => 'everyone',
    [final one] => one,
    [final one, final other] => '$one and $other',
    _ => '${names.length} people',
  };
}
