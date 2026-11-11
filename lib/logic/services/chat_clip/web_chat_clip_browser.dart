/// The web half of [web_chat_clip.dart] — the real browser calls.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;
import 'dart:ui_web' as ui_web;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import '../../../data/repositories/blob/blob_reader.dart';
import '../../../src/rust/api/clips.dart';
import '../../helper_methods.dart';
import 'chat_clip.dart';
import 'web_clip_stream.dart';

/// A chat video played by the browser's own `<video>`, so the browser's
/// decoders do the work, from a URL the page itself answers: a big one is
/// fetched as the player reads it, through Rift's service worker
/// ([WebClipStream]), and one already in memory, or one played where there
/// is no worker, from a `blob:` URL over the whole of it. Either way the
/// decrypted file never leaves memory.
///
/// The element is made here, not by the view, so it loads and plays the
/// same whether or not the card is drawing it; [picture] puts it on the
/// page. It takes no pointer: the card's own controls sit over it.
class WebChatClip implements ChatClip {
  WebChatClip._(this._id, this._video, this._url, this._file, this._events) {
    _watching = [
      web.EventStreamProviders.loadedMetadataEvent
          .forTarget(_video)
          .listen((_) => _sayShape()),
      web.EventStreamProviders.resizeEvent
          .forTarget(_video)
          .listen((_) => _sayShape()),
      web.EventStreamProviders.endedEvent
          .forTarget(_video)
          .listen((_) => _say(ClipEventKind.ended)),
      web.EventStreamProviders.errorEvent
          .forTarget(_video)
          .listen((_) => _failed()),
    ];
  }

  static const bool available = true;

  /// The one view type every clip is drawn through; each view finds its
  /// clip by the id in its creation parameters.
  static const String _viewType = 'rift-chat-clip';
  static bool _registered = false;
  static int _next = 1;
  static final Map<int, web.HTMLVideoElement> _videos = {};

  static void _register() {
    if (_registered) return;
    _registered = true;
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (
      int viewId, {
      Object? params,
    }) {
      // A view drawn after its clip closed shows nothing.
      return _videos[params as int?] ?? web.HTMLDivElement();
    });
  }

  final int _id;
  final web.HTMLVideoElement _video;
  final String _url;

  /// What [_url] is read from, where the worker serves it; null for a
  /// `blob:` URL.
  final BlobReader? _file;
  final StreamController<ClipEvent> _events;
  late final List<StreamSubscription<web.Event>> _watching;
  (int, int)? _shape;
  bool _closed = false;

  @override
  Stream<ClipEvent> get events => _events.stream;

  /// Installs the worker that streams a big video, so it is in control by
  /// the first one played.
  static Future<void> prepare() => WebClipStream.start();

  /// [ChatClip.open] in a `<video>`. [output] is a browser device id; a
  /// browser that cannot choose (Safari, Firefox before 116) plays on the
  /// default. [type] is the file's media type, which Safari wants.
  static Future<({ChatClip? clip, String? error})> open(
    BlobReader file, {
    String? output,
    String? type,
  }) async {
    _register();
    final streamed = file is MemoryBlobReader
        ? null
        : WebClipStream.urlFor(file, type: type);
    final String url;
    if (streamed != null) {
      url = streamed;
    } else {
      try {
        final bytes = await file.readFully(0, file.length);
        url = web.URL.createObjectURL(
          web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: type ?? '')),
        );
      } catch (e) {
        HelperMethods.printDebug('[ChatClip] open: ${e.runtimeType}');
        return (clip: null, error: '$e');
      } finally {
        await file.close();
      }
    }
    final video = _element(url);
    if (output != null && output.isNotEmpty && video.has('setSinkId')) {
      unawaited(
        video.setSinkId(output).toDart.catchError((Object e) {
          HelperMethods.printDebug('[ChatClip] output: $e');
          return null;
        }),
      );
    }
    final id = _next++;
    _videos[id] = video;
    // Not a broadcast: what the player says before the card listens waits
    // for it.
    final clip = WebChatClip._(
      id,
      video,
      url,
      streamed == null ? null : file,
      StreamController<ClipEvent>(),
    );
    return (clip: clip, error: null);
  }

  static web.HTMLVideoElement _element(String url) {
    final video = web.HTMLVideoElement()
      ..preload = 'auto'
      ..playsInline = true
      ..controls = false;
    video.style
      ..width = '100%'
      ..height = '100%'
      ..objectFit = 'contain'
      ..pointerEvents = 'none'
      ..display = 'block';
    video.src = url;
    return video;
  }

  void _sayShape() {
    final shape = (_video.videoWidth, _video.videoHeight);
    if (shape.$1 == 0 || shape.$2 == 0 || shape == _shape) return;
    _shape = shape;
    _say(ClipEventKind.pictureSize, width: shape.$1, height: shape.$2);
  }

  void _failed() {
    final error = _video.error;
    // MEDIA_ERR_DECODE and MEDIA_ERR_SRC_NOT_SUPPORTED: what the file holds
    // is not something this browser plays.
    final unplayable = error != null && (error.code == 3 || error.code == 4);
    HelperMethods.printDebug(
      '[ChatClip] error ${error?.code}: ${error?.message ?? ''}',
    );
    _say(
      unplayable ? ClipEventKind.cannotDecode : ClipEventKind.failed,
      reason: error?.message ?? '',
    );
  }

  void _say(
    ClipEventKind kind, {
    int width = 0,
    int height = 0,
    String reason = '',
  }) {
    if (_closed) return;
    _events.add(
      ClipEvent(
        texture: BigInt.from(_id),
        kind: kind,
        width: width,
        height: height,
        reason: reason,
      ),
    );
  }

  @override
  Widget picture() => HtmlElementView(viewType: _viewType, creationParams: _id);

  @override
  Future<bool> play() async {
    try {
      await _video.play().toDart;
      return true;
    } catch (e) {
      // Most often NotAllowedError: sound that no click asked for just then.
      HelperMethods.printDebug('[ChatClip] play: $e');
      return false;
    }
  }

  @override
  Future<void> pause() async => _video.pause();

  @override
  Future<void> seek(Duration to) async {
    _video.currentTime = math.max(0, to.inMilliseconds) / 1000;
  }

  @override
  Future<void> setVolume(double volume) async {
    _video.volume = volume.clamp(0, 1).toDouble();
  }

  @override
  ({Duration? position, Duration? length}) time() {
    Duration? of(double seconds) => seconds.isFinite && seconds >= 0
        ? Duration(milliseconds: (seconds * 1000).round())
        : null;
    return (position: of(_video.currentTime), length: of(_video.duration));
  }

  /// Stops it, empties the element so the browser lets its buffers go, then
  /// the file.
  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final watch in _watching) {
      await watch.cancel();
    }
    _videos.remove(_id);
    _video
      ..pause()
      ..removeAttribute('src')
      ..load();
    if (_file case final file?) {
      WebClipStream.forget(_url);
      await file.close();
    } else {
      web.URL.revokeObjectURL(_url);
    }
    await _events.close();
  }

  // ── Poster ──────────────────────────────────────────────────────────────

  /// How long the first picture may take before there is no poster.
  static const Duration _patience = Duration(seconds: 10);

  /// [ChatClip.poster]: the first picture drawn by a silent `<video>` onto
  /// a canvas and encoded there, without sound or a view.
  static Future<Uint8List?> poster(Uint8List video, {int longest = 880}) async {
    final String url;
    try {
      url = web.URL.createObjectURL(web.Blob([video.toJS].toJS));
    } catch (e) {
      HelperMethods.printDebug('[ChatClip] poster: $e');
      return null;
    }
    try {
      return await posterAt(url, longest: longest);
    } finally {
      web.URL.revokeObjectURL(url);
    }
  }

  /// [poster] of the video at [url], a picked file's blob URL, which the
  /// browser reads where it lies: a big one is never copied into memory.
  static Future<Uint8List?> posterAt(String url, {int longest = 880}) async {
    final element = _element(url)..muted = true;
    try {
      final ready = Completer<bool>();
      final watching = [
        web.EventStreamProviders.loadedDataEvent
            .forTarget(element)
            .listen((_) => ready.isCompleted ? null : ready.complete(true)),
        web.EventStreamProviders.errorEvent
            .forTarget(element)
            .listen((_) => ready.isCompleted ? null : ready.complete(false)),
      ];
      final loaded = await ready.future.timeout(
        _patience,
        onTimeout: () => false,
      );
      for (final watch in watching) {
        await watch.cancel();
      }
      if (!loaded) return null;
      final (w, h) = _posterSize((
        element.videoWidth,
        element.videoHeight,
      ), longest);
      if (w == 0 || h == 0) return null;
      final canvas = web.HTMLCanvasElement()
        ..width = w
        ..height = h;
      final context = canvas.getContext('2d') as web.CanvasRenderingContext2D?;
      if (context == null) return null;
      context.drawImage(element, 0, 0, w, h);
      return await _jpeg(canvas);
    } catch (e) {
      HelperMethods.printDebug('[ChatClip] poster: $e');
      return null;
    } finally {
      element
        ..removeAttribute('src')
        ..load();
    }
  }

  static Future<Uint8List?> _jpeg(web.HTMLCanvasElement canvas) {
    final done = Completer<Uint8List?>();
    canvas.toBlob(
      ((web.Blob? blob) {
        if (blob == null) return done.complete(null);
        blob.arrayBuffer().toDart.then(
          (buffer) => done.complete(buffer.toDart.asUint8List()),
          onError: (Object e) => done.complete(null),
        );
      }).toJS,
      'image/jpeg',
      0.8.toJS,
    );
    return done.future;
  }
}

/// [shown] shrunk to fit [longest] on its longer side, never grown, as the
/// Rust posters are; 0 × 0 when it has no size.
(int, int) _posterSize((int, int) shown, int longest) {
  final (w, h) = shown;
  if (w <= 0 || h <= 0) return (0, 0);
  final longer = math.max(w, h);
  if (longer <= longest) return (w, h);
  int scale(int side) => math.max(1, (side * longest / longer).round());
  return (scale(w), scale(h));
}
