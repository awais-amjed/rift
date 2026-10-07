import 'package:cross_file/cross_file.dart';

import '../../../data/repositories/blob/blob_sink.dart';

/// A [BlobSink] that ends up somewhere the person can find it.
abstract interface class SaveSink implements BlobSink {
  /// Whether the file reached its place. False after an [abort], and on a
  /// phone whose save dialog was dismissed once the download was done.
  bool get saved;
}

/// A [BlobSink] for a file on its way somewhere else — a forward, downloaded
/// to be sent again — which [file] reads back once it is closed.
abstract interface class ScratchSink implements BlobSink {
  /// The file, once [close]d. Read it before [discard].
  XFile get file;

  /// Remove it, once it has been sent on.
  Future<void> discard();
}
