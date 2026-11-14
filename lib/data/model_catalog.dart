import 'dart:io';

import 'package:flutter/foundation.dart';

import 'classes/model_file.dart';

/// Every file Rift downloads instead of shipping, each pinned to its hash.
///
/// They were in the installers until Nov 2026, most of the download for
/// models only some people use. Now each one is fetched the first time
/// something needs it and kept, across updates and for every profile on the
/// device (`ModelRepository`). Change a file by adding it to the release under
/// a new name (`scripts/upload_models.sh` prints the entry) and replacing its
/// line here; never edit a hash on its own.
abstract final class ModelCatalog {
  /// The picture classifier (`ImageSafetyClassifier`), fetched first at the
  /// first start: until it lands, pictures are shown without a check. The
  /// web serves its own copy beside the app (`scripts/build_web.sh`).
  static const imageSafety = ModelFile(
    id: 'image_safety',
    name: 'picture safety model',
    published: 'image_safety.v1.tflite',
    size: 12265328,
    sha256: '82900132da38c1f30ee65d2d7908a00b78df9f96fba66ce69b0aea909f01d559',
  );

  /// DPDFNet's weights for Ceva's runtime, DPDFNet-8's and DPDFNet-2's,
  /// each `weights.f32` as Ceva ships it (`native/dpdfnet`). Fetched on a
  /// desktop the first time DPDFNet is put on, which is at the first start,
  /// since it is the default (`NoiseFilter`); not where ONNX Runtime runs the
  /// models instead ([dpdfnetOnnxLarge]).
  static const dpdfnetLarge = ModelFile(
    id: 'dpdfnet8',
    name: 'noise model',
    published: 'dpdfnet8.ceva.v1.f32',
    size: 14532272,
    sha256: '5a5bb67a8619090c54dc2793536fe813fe38123b236d445f3433aafe3075529d',
  );
  static const dpdfnetSmall = ModelFile(
    id: 'dpdfnet2',
    name: 'small noise model',
    published: 'dpdfnet2.ceva.v1.f32',
    size: 10329776,
    sha256: 'cb7248b8fccbff7b32f254ec2ed0061e604514b2ccd98d997cd081a876424e7b',
  );

  /// DPDFNet for ONNX Runtime, on a desktop where Ceva's runtime cannot run
  /// (no AVX2 and FMA): DPDFNet-8 and DPDFNet-2 as Ceva publishes them
  /// (huggingface.co/Ceva-IP/DPDFNet, `onnx/`), fetched with
  /// [onnxRuntime] in place of the weights above.
  static const dpdfnetOnnxLarge = ModelFile(
    id: 'dpdfnet8_onnx',
    name: 'noise model',
    published: 'dpdfnet8_48khz_hr.v1.onnx',
    size: 14857107,
    sha256: '7b3afbb260a08fe9af3d16e3bda992971be1e7e951d1dee7c2d235f5c43f5631',
  );
  static const dpdfnetOnnxSmall = ModelFile(
    id: 'dpdfnet2_onnx',
    name: 'small noise model',
    published: 'dpdfnet2_48khz_hr.v1.onnx',
    size: 10493337,
    sha256: '7f0575a5cec0ba4ffd8f8bd657e06d007e4ccdd955d76faab922b9d3291dc14b',
  );

  /// ONNX Runtime 1.28.2, Microsoft's CPU build, the library alone from its
  /// release archive; its licences are in `assets/licenses/onnxruntime.txt`.
  static const onnxRuntimeLinux = ModelFile(
    id: 'onnxruntime',
    name: 'noise model runtime',
    published: 'libonnxruntime.linux-x64.1.28.2.so',
    size: 24277040,
    sha256: '088f24b1fc56714d3efaaeb3ac2ee486a5d7b50ccfbb3dd26fd1a612534a05fb',
  );
  static const onnxRuntimeWindows = ModelFile(
    id: 'onnxruntime',
    name: 'noise model runtime',
    published: 'onnxruntime.win-x64.1.28.2.dll',
    size: 15818040,
    sha256: '1becbd71adbf49609d33195e29c9214969db3c3de69c81425bebe5a4b69aef97',
  );

  /// This computer's ONNX Runtime, or null where DPDFNet does not run.
  static ModelFile? get onnxRuntime {
    if (kIsWeb) return null;
    if (Platform.isLinux) return onnxRuntimeLinux;
    if (Platform.isWindows) return onnxRuntimeWindows;
    return null;
  }

  /// RNNoise's weights, which the runner leaves out (`native/noise_filter`),
  /// as RNNoise's own `write_weights.c` writes them from the model in
  /// `third_party/rnnoise` (`scripts/upload_models.sh`). Fetched on a desktop
  /// the first time RNNoise is put on (`NoiseFilter`).
  static const rnnoise = ModelFile(
    id: 'rnnoise',
    name: 'RNNoise model',
    published: 'rnnoise.v1.bin',
    size: 3544320,
    sha256: '1ad07b428be34c74d9678d05b3c387b73ccf0e6203a1a5f9ce58689b30b303c8',
  );

  /// Every file DPDFNet may be loaded from, on either runtime.
  static const dpdfnet = [
    dpdfnetLarge,
    dpdfnetSmall,
    dpdfnetOnnxLarge,
    dpdfnetOnnxSmall,
    onnxRuntimeLinux,
    onnxRuntimeWindows,
  ];

  /// Every file this version of the app may use. What else is in the
  /// folder belongs to another version, and is swept once nothing has used it
  /// for a while.
  static const all = [imageSafety, rnnoise, ...dpdfnet];
}
