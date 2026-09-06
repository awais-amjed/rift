import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_litert/flutter_litert.dart';

import 'image_safety.dart';

/// The on-device NSFW classifier: `image-safety-classifier-xs`, a 3.5M
/// parameter SwiftFormer converted to LiteRT (see `~/dev/rift-models`).
///
/// It runs on the bytes this device decrypted and nowhere else. Every message
/// and attachment is end-to-end encrypted, so the server never sees a picture
/// and could not scan one; the only place a verdict can be reached is here,
/// after the decrypt, and the only thing it decides is whether *this* device
/// draws the picture plainly.
///
/// One interpreter for the app, loaded on first use and kept. Inference goes
/// through an isolate on native platforms so a burst of thumbnails cannot
/// stall the frame; the web has no isolates and runs it inline, where a
/// model this small is still a few milliseconds.
class ImageSafetyClassifier {
  ImageSafetyClassifier._();

  static final ImageSafetyClassifier instance = ImageSafetyClassifier._();

  static const String asset = 'assets/models/image_safety.tflite';

  /// The model's fixed input edge. Images are resized straight to this, not
  /// letterboxed — the same stretch the model card's own example uses.
  static const int side = 224;

  Interpreter? _interpreter;
  IsolateInterpreter? _isolate;
  Future<bool>? _loading;
  bool _channelsFirst = false;

  /// Verdicts by attachment id. A thumbnail is built many times as a list
  /// scrolls; the model runs once.
  final Map<String, ImageSafetyVerdict> _verdicts = {};

  ImageSafetyVerdict? cached(String id) => _verdicts[id];

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
      debugPrint('ImageSafetyClassifier: could not decode – $e');
      return null;
    }

    final input = _channelsFirst
        ? pixels.reshape([1, 3, side, side])
        : pixels.reshape([1, side, side, 3]);
    final output = [List<double>.filled(3, 0)];
    try {
      final isolate = _isolate;
      if (isolate != null) {
        await isolate.run(input, output);
      } else {
        _interpreter!.run(input, output);
      }
    } catch (e) {
      debugPrint('ImageSafetyClassifier: inference failed – $e');
      return null;
    }

    final verdict = ImageSafetyVerdict.fromScores(output[0]);
    _verdicts[id] = verdict;
    return verdict;
  }

  Future<bool> _load() => _loading ??= _loadOnce();

  Future<bool> _loadOnce() async {
    try {
      final options = InterpreterOptions()..threads = 2;
      final interpreter = await Interpreter.fromAsset(asset, options: options);
      final shape = interpreter.getInputTensors().first.shape;
      // The converter is asked for NHWC, but a model that kept the ONNX
      // layout is still usable — the pixels are just packed the other way.
      _channelsFirst = shape.length == 4 && shape[1] == 3;
      _interpreter = interpreter;
      if (!kIsWeb) {
        _isolate = await IsolateInterpreter.create(
          address: interpreter.address,
        );
      }
      return true;
    } catch (e) {
      debugPrint('ImageSafetyClassifier: model unavailable – $e');
      return false;
    }
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
