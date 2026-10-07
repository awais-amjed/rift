import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/api_response.dart';
import 'package:rift/data/classes/attachment.dart';
import 'package:rift/data/repositories/attachment_repository.dart';
import 'package:rift/data/repositories/blob/blob_sink.dart';
import 'package:rift/logic/services/attachment_loader.dart';

class _Owner {
  Future<Uint8List?> load(Attachment attachment) async => null;
  Future<APIResponse> save(
    Attachment attachment,
    BlobSink sink, {
    TransferProgress? onProgress,
  }) async => APIResponse(success: true);

  AttachmentLoader get loader => AttachmentLoader(load: load, save: save);
}

/// A chat cubit hands its loader out from a getter, so each rebuild makes a
/// new one. A thumbnail refetches when the loader changes, and by identity
/// that was every rebuild: the picture flickered back to its placeholder.
void main() {
  test('loaders from the same owner are equal', () {
    final owner = _Owner();
    expect(owner.loader, owner.loader);
    expect(owner.loader.hashCode, owner.loader.hashCode);
  });

  test('loaders from different owners are not', () {
    expect(_Owner().loader == _Owner().loader, isFalse);
  });
}
