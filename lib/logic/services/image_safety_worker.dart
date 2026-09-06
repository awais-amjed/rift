import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_litert/flutter_litert.dart';

/// A long-lived isolate that owns one [CompiledModel] and answers pixel
/// buffers with class scores.
///
/// LiteRT Next's compiled path runs this model four times faster than the
/// classic interpreter on the CPU (23 ms against 88 ms on a laptop), but it
/// has no isolate wrapper of its own the way `IsolateInterpreter` does, and
/// 23 ms is still more than a frame. So the model lives on its own isolate,
/// compiled once, and each picture is one message across.
///
/// Native only: the web has no isolates, and the classifier keeps the classic
/// interpreter there.
class ImageSafetyWorker {
  final Isolate _isolate;
  final SendPort _requests;

  ImageSafetyWorker._(this._isolate, this._requests);

  /// Spawn the isolate and compile [modelBytes] on it. Throws when the model
  /// cannot be compiled, so the caller can fall back.
  static Future<ImageSafetyWorker> start(Uint8List modelBytes) async {
    final ready = ReceivePort();
    final isolate = await Isolate.spawn(_main, (
      modelBytes,
      ready.sendPort,
    ), debugName: 'image-safety');
    final first = await ready.first;
    ready.close();
    if (first is SendPort) return ImageSafetyWorker._(isolate, first);
    isolate.kill();
    throw StateError('image safety model failed to compile: $first');
  }

  /// Scores for one [1, side, side, 3] float buffer, in class order.
  Future<List<double>> run(Float32List pixels) async {
    final reply = ReceivePort();
    _requests.send((TransferableTypedData.fromList([pixels]), reply.sendPort));
    final answer = await reply.first;
    reply.close();
    if (answer is Float32List) return answer.toList();
    throw StateError('image safety inference failed: $answer');
  }

  void close() {
    _requests.send(null);
    _isolate.kill(priority: Isolate.immediate);
  }

  static void _main((Uint8List, SendPort) args) {
    final (bytes, ready) = args;
    final CompiledModel model;
    try {
      model = CompiledModel.fromBuffer(
        bytes,
        accelerators: const {Accelerator.cpu},
      );
    } catch (e) {
      ready.send(e.toString());
      return;
    }
    final requests = ReceivePort();
    ready.send(requests.sendPort);
    requests.listen((message) {
      if (message == null) {
        model.close();
        requests.close();
        return;
      }
      final (data, reply) = message as (TransferableTypedData, SendPort);
      try {
        final pixels = data.materialize().asFloat32List();
        reply.send(model.run([pixels]).first);
      } catch (e) {
        reply.send(e.toString());
      }
    });
  }
}
