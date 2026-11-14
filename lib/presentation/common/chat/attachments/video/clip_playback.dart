import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../data/classes/attachment.dart';
import '../../../../../data/repositories/blob/blob_reader.dart';
import '../../../../../logic/services/chat_clip/chat_clip.dart';
import '../../../../../src/rust/api/clips.dart';
import '../attachment_loader.dart';

/// One chat video's playing: the [ChatClip] once it is open, and what the
/// controls draw from it.
///
/// Held by the card, and shared with the full-screen page while that is
/// open, so the video goes on where it was when it is made bigger or
/// smaller. Only one of the two draws the picture at a time ([fullscreen]):
/// on the web a clip is one `<video>`, which can sit in one place only.
class ClipPlayback extends ChangeNotifier {
  final Attachment attachment;
  final AttachmentLoader loader;

  ClipPlayback({required this.attachment, required this.loader})
    : length = Duration(milliseconds: attachment.durationMs ?? 0);

  ChatClip? clip;
  StreamSubscription<ClipEvent>? _events;
  Timer? _ticker;
  bool _disposed = false;

  bool opening = false;
  bool playing = false;
  bool ended = false;

  /// Why it cannot play here, in words; null while it can.
  String? problem;

  /// The picture's shape, once the player has said it.
  Size? picture;
  Duration position = Duration.zero;
  Duration length;

  /// Whether the full-screen page has it, and draws the picture.
  bool fullscreen = false;

  /// The card went while the page had it: the list let it go, scrolled out
  /// of reach by messages arriving. The page then closes it as it leaves,
  /// rather than the video stopping under somebody watching it.
  bool cardGone = false;

  /// What the clip plays at: the app's chat video volume, or nothing while
  /// muted. Kept here too so a clip opened later starts at it.
  double _volume = 1;

  /// Reads in a row, while playing, where the player said the same place:
  /// it is waiting for the file, most often after a seek past what has been
  /// fetched. No player says so in the same words, but each one's clock
  /// stops while it waits.
  int _stillReads = 0;
  Duration? _lastRead;

  /// Where the player says it is waiting (ExoPlayer): said for long enough
  /// to show. It waits a moment even for a seek into what is already here.
  bool _toldWaiting = false;
  Timer? _waitingShows;


  void _changed() {
    if (!_disposed) notifyListeners();
  }

  /// Play or pause, opening it first if it is not open yet. [output] is the
  /// device its sound goes to, read when it opens.
  Future<void> toggle({String? output}) async {
    if (opening || problem != null) return;
    final clip = this.clip;
    if (clip == null) return _open(output);
    if (playing) {
      await clip.pause();
      _setPlaying(false);
      return;
    }
    if (ended) {
      await clip.seek(Duration.zero);
      ended = false;
      position = Duration.zero;
      _changed();
    }
    _setPlaying(await clip.play());
  }

  /// Stopped where it is: Rift went out of sight on a phone.
  void pause() {
    final clip = this.clip;
    if (clip == null || !playing) return;
    unawaited(clip.pause());
    _setPlaying(false);
  }

  Future<void> _open(String? output) async {
    opening = true;
    _changed();
    final file = await _file();
    final reader = file.reader;
    if (_disposed) {
      await reader?.close();
      return;
    }
    if (reader == null) {
      opening = false;
      problem = file.problem;
      _changed();
      return;
    }
    final opened = await ChatClip.open(
      reader,
      output: output,
      type: attachment.mime,
    );
    final clip = opened.clip;
    if (_disposed) {
      await clip?.close();
      return;
    }
    if (clip == null) {
      opening = false;
      problem = 'This video could not be played.';
      _changed();
      return;
    }
    _events = clip.events.listen(_heard);
    clip.waiting?.addListener(_waitingChanged);
    this.clip = clip;
    opening = false;
    _changed();
    await clip.setVolume(_volume);
    _setPlaying(await clip.play());
  }

  /// What the player reads: the file fetched as it plays where it can be,
  /// or else the whole of it, when that is small enough to hold.
  Future<({BlobReader? reader, String? problem})> _file() async {
    final streamed = loader.readerFor(attachment);
    if (streamed != null) return (reader: streamed, problem: null);
    if (attachment.size > ChatClip.wholeMaxBytes) {
      return (
        reader: null,
        problem: 'This video is too big to play here. Save it to watch it.',
      );
    }
    final bytes = await loader(attachment);
    if (bytes == null) {
      return (reader: null, problem: 'This video could not be downloaded.');
    }
    return (reader: MemoryBlobReader(bytes), problem: null);
  }

  void _heard(ClipEvent event) {
    if (_disposed) return;
    switch (event.kind) {
      case ClipEventKind.pictureSize:
        picture = Size(event.width.toDouble(), event.height.toDouble());
        _changed();
      case ClipEventKind.ended:
        // The player itself still means to play: ExoPlayer and GStreamer
        // play on from wherever a seek after the end lands, under controls
        // that say it stopped. Paused, a seek there shows that picture only.
        unawaited(clip?.pause());
        _setPlaying(false);
        ended = true;
        position = length;
        _changed();
      case ClipEventKind.cannotDecode:
        _fail(
          "This video's format doesn't play ${_here()}. Save it to watch it.",
        );
      case ClipEventKind.failed:
        _fail('This video could not be played.');
    }
  }

  static String _here() => kIsWeb
      ? 'in this browser'
      : defaultTargetPlatform == TargetPlatform.android
      ? 'on this phone'
      : 'on this computer';

  void _fail(String why) {
    _setPlaying(false);
    _letGo();
    problem = why;
    _changed();
  }

  void _waitingChanged() {
    final waiting = clip?.waiting?.value ?? false;
    _waitingShows?.cancel();
    if (!waiting) {
      if (_toldWaiting) {
        _toldWaiting = false;
        _changed();
      }
      return;
    }
    _waitingShows = Timer(const Duration(milliseconds: 150), () {
      _toldWaiting = true;
      _changed();
    });
  }

  /// Playing, and the time read while it is: the player has no clock of
  /// its own to send.
  void _setPlaying(bool now) {
    if (_disposed) return;
    playing = now;
    _stillReads = 0;
    _lastRead = null;
    _changed();
    _ticker?.cancel();
    if (!now) return;
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => _read());
  }

  void _read() {
    final time = clip?.time();
    if (time == null || _disposed) return;
    _stillReads = time.position == _lastRead ? _stillReads + 1 : 0;
    _lastRead = time.position;
    if (time.position != null) position = time.position!;
    if (time.length != null && time.length! > Duration.zero) {
      length = time.length!;
    }
    _changed();
  }

  Future<void> seek(Duration to) async {
    final clip = this.clip;
    if (clip == null) return;
    if (length > Duration.zero && to > length) to = length;
    if (to < Duration.zero) to = Duration.zero;
    position = to;
    ended = false;
    _stillReads = 0;
    _lastRead = null;
    _changed();
    await clip.seek(to);
  }

  /// Forward or back by [by], from where it is.
  Future<void> skip(Duration by) => seek(position + by);

  /// The volume to play at, 0 to 1: the app's setting, or 0 while muted.
  void setVolume(double volume) {
    if (volume == _volume) return;
    _volume = volume;
    final clip = this.clip;
    if (clip != null) unawaited(clip.setVolume(volume));
  }

  /// Playing, but waiting for the file: the dots, so a seek past what has
  /// been fetched does not look like a frozen video. Where the player does
  /// not say so, stuck where it is for half a second, but not in the last
  /// moment before the end, which the end's own event follows.
  bool get waiting {
    if (!playing) return false;
    if (clip?.waiting != null) return _toldWaiting;
    return _stillReads >= 2 &&
        (length <= Duration.zero ||
            position < length - const Duration(milliseconds: 500));
  }

  /// Said by the page as it comes and goes, which is in the middle of a
  /// build: the card is told after the frame, and any build before then
  /// already reads the new value.
  void setFullscreen(bool on) {
    if (fullscreen == on) return;
    fullscreen = on;
    SchedulerBinding.instance.addPostFrameCallback((_) => _changed());
  }

  void _letGo() {
    _ticker?.cancel();
    _waitingShows?.cancel();
    clip?.waiting?.removeListener(_waitingChanged);
    _toldWaiting = false;
    _events?.cancel();
    unawaited(clip?.close());
    clip = null;
  }

  /// Stops it and lets the file go: the card's to call, or the full-screen
  /// page's once the card has gone ([cardGone]).
  @override
  void dispose() {
    _disposed = true;
    _letGo();
    super.dispose();
  }
}
