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

  /// Every file this version of the app may use. What else is in the
  /// folder belongs to another version, and is swept once nothing has used it
  /// for a while.
  static const all = [imageSafety];
}
