/// How the browser's `<video>` reads a chat video as it is fetched.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../../../data/repositories/blob/blob_reader.dart';
import '../../helper_methods.dart';

/// Hands a `<video>` a chat video a piece at a time, through Rift's service
/// worker (`web/clip-sw.js`, where the conversation between the two is set
/// out).
///
/// A `<video>` reads a URL. A `blob:` one needs the whole file in memory
/// first, so a big video would be fetched and decrypted whole before it
/// played. Instead the video's URL is one the worker answers, and the worker
/// asks this page for each range the player wants, read from the video's
/// [BlobReader] — fetched and opened as it is read, never held whole and
/// never on a disk. Only this page can answer for its own videos.
///
/// Where the worker is not in control of the page (a private window in
/// Firefox, a page that is not a secure origin, the moment before the first
/// one installs), [urlFor] says so and the video is read whole, as before.
class WebClipStream {
  static const String _script = 'clip-sw.js';
  static const String _prefix = '__rift_clip/';

  /// The most one read hands over, as the worker asks: a sealed chunk.
  static const int _maxRead = 1 << 20;

  /// How often the page tells the worker a video is still open. A browser
  /// stops an idle worker after half a minute, which would cut off a paused
  /// video's request.
  static const Duration _heartbeat = Duration(seconds: 10);

  static final Map<String, _Clip> _clips = {};
  static final math.Random _random = math.Random.secure();
  static bool _started = false;
  static Timer? _alive;

  /// Installs the worker and starts answering it. Called at start, so it is
  /// in control by the time anyone plays a video.
  static Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      final workers = _workers;
      if (workers == null) return;
      workers.addEventListener('message', _heard.toJS);
      workers.startMessages();
      final base = Uri.parse(web.document.baseURI);
      await workers
          .register(
            base.resolve(_script).toString().toJS,
            web.RegistrationOptions(
              scope: base.resolve('./').toString(),
              updateViaCache: 'none',
            ),
          )
          .toDart;
    } catch (e) {
      HelperMethods.printDebug('[ChatClip] worker: $e');
    }
  }

  /// Null where the browser has no service workers here.
  static web.ServiceWorkerContainer? get _workers =>
      web.window.navigator.has('serviceWorker')
      ? web.window.navigator.serviceWorker
      : null;

  static bool get _inControl {
    try {
      return _workers?.controller?.scriptURL.endsWith(_script) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// The URL a `<video>` plays [file] from, with [type] as its media type;
  /// null where the worker cannot serve it. [file] stays the caller's to
  /// close, after [forget].
  static String? urlFor(BlobReader file, {String? type}) {
    if (!_inControl) return null;
    final token = [
      for (var i = 0; i < 16; i++) _random.nextInt(256),
    ].map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    _clips[token] = _Clip(file, type);
    _alive ??= Timer.periodic(_heartbeat, (_) => _ping());
    return Uri.parse(web.document.baseURI).resolve('$_prefix$token').toString();
  }

  /// Stops answering for the video at [url]: a request still open for it
  /// fails at its next read.
  static void forget(String url) {
    _clips.remove(Uri.parse(url).pathSegments.last);
    if (_clips.isNotEmpty) return;
    _alive?.cancel();
    _alive = null;
  }

  static void _ping() {
    try {
      _workers?.controller?.postMessage('alive'.toJS);
    } catch (_) {}
  }

  /// A request for one of this page's videos: its port carries the rest.
  static void _heard(web.MessageEvent event) {
    final data = event.data;
    if (data == null || !data.isA<JSObject>()) return;
    final token = (data as JSObject)['riftClip'];
    if (token == null || !token.isA<JSString>()) return;
    final ports = event.ports.toDart;
    if (ports.isEmpty) return;
    final port = ports.first;
    final clip = _clips[(token as JSString).toDart];
    if (clip == null) {
      port
        ..postMessage(_message({'gone': true.toJS}))
        ..close();
      return;
    }
    port.onmessage = ((web.MessageEvent e) {
      unawaited(_answer(clip, port, e.data));
    }).toJS;
    port.postMessage(
      _message({
        'length': clip.file.length.toJS,
        if (clip.type case final type? when type.isNotEmpty) 'type': type.toJS,
      }),
    );
  }

  static Future<void> _answer(
    _Clip clip,
    web.MessagePort port,
    JSAny? data,
  ) async {
    if (data == null || !data.isA<JSObject>()) return;
    final asked = data as JSObject;
    if (asked.has('done')) return port.close();
    final offset = asked['read'];
    final max = asked['max'];
    if (offset == null || max == null) return;
    try {
      final bytes = await clip.file.read(
        (offset as JSNumber).toDartInt,
        math.min((max as JSNumber).toDartInt, _maxRead),
      );
      // Its own buffer, handed over rather than copied again: a view of
      // the chunk the reader holds would send the whole chunk, and hand it
      // over would take it from the reader.
      final buffer = Uint8List.fromList(bytes).buffer.toJS;
      port.postMessage(_message({'bytes': buffer}), [buffer].toJS);
    } catch (e) {
      port.postMessage(_message({'failed': '${e.runtimeType}'.toJS}));
    }
  }

  static JSObject _message(Map<String, JSAny> fields) {
    final message = JSObject();
    fields.forEach((name, value) => message[name] = value);
    return message;
  }
}

class _Clip {
  final BlobReader file;
  final String? type;

  _Clip(this.file, this.type);
}
