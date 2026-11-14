import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_litert/flutter_litert.dart';

import '../../data/model_catalog.dart';
import '../../data/repositories/model_repository.dart';
import '../helper_methods.dart';
import 'image_safety.dart';
import 'image_safety_worker.dart';

/// The on-device NSFW classifier: `image-safety-classifier-xs`, a 3.5M
/// parameter SwiftFormer converted to LiteRT (see the `rift-models` repository).
///
/// It runs on the bytes this device decrypted and nowhere else. Every message
/// and attachment is end-to-end encrypted, so the server never sees a picture
/// and could not scan one; the only place a verdict can be reached is here,
/// after the decrypt, and the only thing it decides is whether *this* device
/// draws the picture plainly.
///
/// One model for the app, loaded on first use and kept. On native platforms
/// it is LiteRT Next's compiled path on a worker isolate
/// ([ImageSafetyWorker]) — four times faster than the classic interpreter
/// here, and off the UI thread so a burst of thumbnails cannot stall a
/// frame. The web has no isolates and keeps the classic interpreter inline.
///
/// The model is downloaded, not shipped (`ModelCatalog.imageSafety`). Until
/// it is on the device every verdict is null, so pictures are shown as they
/// were before the classifier existed; the first start fetches it before
/// anything else, while the person is still signing in.
class ImageSafetyClassifier {
  ImageSafetyClassifier._();

  static final ImageSafetyClassifier instance = ImageSafetyClassifier._();

  /// The model in the source tree, which the release and the web build are
  /// given and the tests run.
  static const String sourceFile = 'assets/models/image_safety.tflite';

  /// The model's fixed input edge. Images are resized straight to this, not
  /// letterboxed — the same stretch the model card's own example uses.
  static const int side = 224;

  ImageSafetyWorker? _worker;
  Interpreter? _interpreter;
  Future<bool>? _loading;
  bool _channelsFirst = false;

  /// Verdicts by attachment id. A thumbnail is built many times as a list
  /// scrolls; the model runs once.
  final Map<String, ImageSafetyVerdict> _verdicts = {};

  ImageSafetyVerdict? cached(String id) => _verdicts[id];

  /// Keeps [verdict] for [id]: a video's, reached from its poster or a
  /// picture while it played, so the card is covered at once next time.
  void remember(String id, ImageSafetyVerdict verdict) =>
      _verdicts[id] = verdict;

  /// The verdict for [bytes], or null when the model could not be loaded or
  /// the bytes are not an image this platform decodes. Null means "show it":
  /// a broken classifier must not hide every picture on the server.
  Future<ImageSafetyVerdict?> classify(String id, Uint8List bytes) async {
    final known = _verdicts[id];
    if (known != null) return known;
    if (!await _load()) return null;

    final Float32List pixels;
    try {
      pixels = await _pixels(bytes);
    } catch (e) {
      HelperMethods.printDebug('ImageSafetyClassifier: could not decode – $e');
      return null;
    }

    final verdict = await _score(pixels);
    if (verdict != null) _verdicts[id] = verdict;
    return verdict;
  }

  /// The verdict for one picture already [side] × [side], as RGBA: a frame
  /// of a playing video (`ChatClip.frame`). Not kept, since a video is
  /// many of them; the caller keeps the one that matters ([remember]).
  Future<ImageSafetyVerdict?> classifyFrame(ByteData rgba) async {
    if (!await _load()) return null;
    if (rgba.lengthInBytes != side * side * 4) return null;
    return _score(packPixels(rgba, side, channelsFirst: _channelsFirst));
  }

  /// The model run on [pixels]; null when it failed.
  Future<ImageSafetyVerdict?> _score(Float32List pixels) async {
    final List<double> scores;
    try {
      final worker = _worker;
      if (worker != null) {
        scores = await worker.run(pixels);
      } else {
        final input = _channelsFirst
            ? pixels.reshape([1, 3, side, side])
            : pixels.reshape([1, side, side, 3]);
        final output = [List<double>.filled(3, 0)];
        _interpreter!.run(input, output);
        scores = output[0];
      }
    } catch (e) {
      HelperMethods.printDebug('ImageSafetyClassifier: inference failed – $e');
      return null;
    }

    return ImageSafetyVerdict.fromScores(scores);
  }

  Future<bool> _load() => _loading ??= _loadOnce();

  Future<bool> _loadOnce() async {
    try {
      final bytes = await _modelBytes();
      if (bytes == null) {
        // Not here yet: asked again by the next picture.
        _loading = null;
        return false;
      }
      // The converter is asked for NHWC, but a model that kept the ONNX
      // layout is still usable — the pixels are just packed the other way.
      // The classic interpreter is opened either way: it is what reads the
      // shape, and what answers on the web or if the worker will not start.
      final interpreter = Interpreter.fromBuffer(
        bytes,
        options: InterpreterOptions()..threads = 2,
      );
      final shape = interpreter.getInputTensors().first.shape;
      _channelsFirst = shape.length == 4 && shape[1] == 3;
      _interpreter = interpreter;
      if (!kIsWeb) {
        try {
          _worker = await ImageSafetyWorker.start(bytes);
        } catch (e) {
          HelperMethods.printDebug(
            'ImageSafetyClassifier: compiled path unavailable – $e',
          );
        }
      }
      return true;
    } catch (e) {
      HelperMethods.printDebug('ImageSafetyClassifier: model unavailable – $e');
      return false;
    }
  }

  /// The model, or null while it is still being downloaded. A picture
  /// does not wait for it: what arrives before the model is shown unchecked.
  static Future<Uint8List?> _modelBytes() async {
    const model = ModelCatalog.imageSafety;
    final models = ModelRepository.instance;
    if (kIsWeb) return models.servedBeside(model);
    final file = await models.present(model);
    if (file != null) return file.readAsBytes();
    // Usually already under way since the start; a failure is logged there.
    unawaited(models.fetch(model).then<void>((_) {}, onError: (Object _) {}));
    return null;
  }

  /// Decode and resize on the engine's own thread, then hand back the pixels
  /// the model wants: RGB, 0–255, normalisation baked into the graph.
  Future<Float32List> _pixels(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: side,
      targetHeight: side,
    );
    final frame = await codec.getNextFrame();
    try {
      final rgba = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (rgba == null) throw StateError('no pixel data');
      return packPixels(rgba, side, channelsFirst: _channelsFirst);
    } finally {
      frame.image.dispose();
      codec.dispose();
    }
  }

  /// RGBA bytes to the model's float tensor, alpha dropped.
  ///
  /// NHWC by default — `[y][x][c]` — or NCHW, `[c][y][x]`, for a model that
  /// kept the ONNX layout. Pure, so the packing can be checked without a
  /// model.
  @visibleForTesting
  static Float32List packPixels(
    ByteData rgba,
    int side, {
    bool channelsFirst = false,
  }) {
    final out = Float32List(side * side * 3);
    final plane = side * side;
    for (var p = 0; p < plane; p++) {
      final src = p * 4;
      for (var c = 0; c < 3; c++) {
        final v = rgba.getUint8(src + c).toDouble();
        out[channelsFirst ? c * plane + p : p * 3 + c] = v;
      }
    }
    return out;
  }
}
