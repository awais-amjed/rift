import 'dart:async';

import '../../data/model_catalog.dart';
import '../../data/repositories/model_repository.dart';
import '../helper_methods.dart';

/// Which models a start fetches without being asked, and in what order.
///
/// What every device needs comes down at the first start, the picture
/// classifier first; a model only some people use waits until something asks
/// for it. A start after that finds them here and fetches nothing.
abstract final class ModelDownloads {
  /// Fetches what is missing, then sweeps away what this version no longer
  /// uses. Never throws: a failure is retried when the model is next asked
  /// for, and shown where the progress is. Called before the settings are
  /// read, so the classifier is queued ahead of anything they turn on.
  static Future<void> start() async {
    final models = ModelRepository.instance;
    try {
      await models.fetchFirst(ModelCatalog.imageSafety);
    } on ModelUnavailable {
      // Logged by the repository.
    }
    try {
      await models.sweep(ModelCatalog.all);
    } catch (e) {
      HelperMethods.printDebug('ModelDownloads: sweep – $e');
    }
  }
}
