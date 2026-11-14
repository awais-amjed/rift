part of 'noise_filter_ffi.dart';

/// What DPDFNet runs from, fetched and named to the Rust library, for the
/// call's model and the mic test's: the weights for Ceva's runtime, or where
/// that cannot run, ONNX Runtime and its own copy of the models.
abstract final class _DpdfnetFiles {
  /// The fetch under way or done, once; a failure is tried again on the next
  /// ask.
  static Future<void>? _files;

  /// Fetches DPDFNet's files, if they are not here, and names them to the
  /// Rust library.
  static Future<void> fetch() async {
    final fetching = _files ??= _fetchOnce();
    try {
      await fetching;
    } catch (_) {
      if (identical(_files, fetching)) _files = null;
      rethrow;
    }
  }

  static Future<void> _fetchOnce() async {
    final (runtime, needed) = await _needs();
    // Each set asked together, so the title bar shows it as one download.
    final files = await Future.wait([
      for (final file in needed) ModelRepository.instance.fetch(file),
    ]);
    switch (runtime) {
      case DpdfnetRuntime.none:
        return;
      case DpdfnetRuntime.ceva:
        setDpdfnetWeights(large: files[0].path, small: files[1].path);
      case DpdfnetRuntime.onnx:
        setDpdfnetOnnx(
          large: files[0].path,
          small: files[1].path,
          runtime: files[2].path,
        );
    }
  }

  /// The runtime DPDFNet runs on here, and the files it runs from in the
  /// order [_fetchOnce] hands them on: the weights for Ceva's runtime, or
  /// ONNX Runtime's own copy of the models and the runtime.
  static Future<(DpdfnetRuntime, List<ModelFile>)> _needs() async {
    final runtime = await dpdfnetRuntime();
    final onnx = ModelCatalog.onnxRuntime;
    return switch (runtime) {
      DpdfnetRuntime.ceva => (
        runtime,
        const [ModelCatalog.dpdfnetLarge, ModelCatalog.dpdfnetSmall],
      ),
      DpdfnetRuntime.onnx when onnx != null => (
        runtime,
        [ModelCatalog.dpdfnetOnnxLarge, ModelCatalog.dpdfnetOnnxSmall, onnx],
      ),
      _ => (DpdfnetRuntime.none, const <ModelFile>[]),
    };
  }

  /// Whether DPDFNet's files are all on the device, so it loads without a
  /// download and needs nothing standing in.
  static Future<bool> here() async {
    final (_, needed) = await _needs();
    for (final file in needed) {
      if (await ModelRepository.instance.present(file) == null) return false;
    }
    return true;
  }
}
