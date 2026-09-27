import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/attachment_staging.dart';

/// Picking a file against a server that is running out of disk.
/// The refusal that comes back from Storage is an HTTP 500 with a
/// Postgres error code in it, so this is what a person actually reads.
void main() {
  String? reject({
    int bytes = 1000,
    int maxBytes = 26214400,
    int staged = 0,
    int stagedBytes = 0,
    int? remaining,
  }) => AttachmentStaging.rejectionFor(
    name: 'holiday.png',
    bytes: bytes,
    maxBytes: maxBytes,
    alreadyStaged: staged,
    remainingBytes: remaining,
    stagedBytes: stagedBytes,
  );

  group('attachments against a server storage limit', () {
    test('no limit is no obstacle', () {
      expect(reject(bytes: 20 * 1024 * 1024), isNull);
    });

    test('a file that fits in what is left is accepted', () {
      expect(reject(bytes: 1000, remaining: 1000), isNull);
    });

    test('a file larger than what is left says how much is left', () {
      final message = reject(bytes: 2000, remaining: 1000);
      expect(message, isNotNull);
      expect(message, contains('holiday.png'));
      expect(message, contains('left'));
    });

    test('a full server says so rather than quoting a size', () {
      final message = reject(bytes: 10, remaining: 0);
      expect(message, contains('out of attachment space'));
    });

    test('files already staged count against what is left', () {
      // Each one fits on its own; together they do not. A per-file check
      // alone would wave all five through and fail on upload.
      expect(reject(bytes: 400, remaining: 1000, stagedBytes: 0), isNull);
      expect(reject(bytes: 400, remaining: 1000, stagedBytes: 400), isNull);
      expect(reject(bytes: 400, remaining: 1000, stagedBytes: 800), isNotNull);
    });

    test('too big for one file is said before the server being full', () {
      // Not the server's fault and not fixable by an admin freeing space, so
      // it is the more useful of the two sentences.
      final message = reject(bytes: 5000, maxBytes: 1000, remaining: 0);
      expect(message, contains('per file'));
    });
  });
}
