import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/attachment_staging.dart';
import 'package:rift/logic/services/byte_format.dart';
import 'package:rift/logic/services/limit_input.dart';

void main() {
  group('LimitInput.parse', () {
    test('blank is null — "not set", which is not the same as zero', () {
      expect(LimitInput.parse(''), isNull);
      expect(LimitInput.parse('   '), isNull);
    });

    test('zero is a real answer meaning no limit', () {
      expect(LimitInput.parse('0'), 0);
    });

    test('a plain number, with surrounding space forgiven', () {
      expect(LimitInput.parse('50'), 50);
      expect(LimitInput.parse('  50 '), 50);
    });

    test('nonsense is invalid rather than an exception', () {
      expect(LimitInput.parse('lots'), LimitInput.invalid);
      expect(LimitInput.parse('1.5'), LimitInput.invalid);
      expect(LimitInput.parse('-1'), LimitInput.invalid);
    });
  });

  group('LimitInput.parseMegabytes', () {
    test('megabytes in, bytes out', () {
      expect(LimitInput.parseMegabytes('25'), 26214400);
      expect(LimitInput.parseMegabytes('1'), 1048576);
    });

    test('blank stays null so the caller can ask for a value', () {
      expect(LimitInput.parseMegabytes(''), isNull);
    });

    test('zero is refused — a size has no "off"', () {
      // The one place 0 does *not* mean unlimited: a cap of zero bytes would
      // forbid every attachment rather than allow every attachment.
      expect(LimitInput.parseMegabytes('0'), LimitInput.invalid);
    });

    test('nonsense is invalid', () {
      expect(LimitInput.parseMegabytes('big'), LimitInput.invalid);
    });
  });

  group('LimitInput display', () {
    test('bytes round up to whole megabytes, never down', () {
      // Rounding down would show a cap as smaller than it is, and an admin
      // saving the form back would then quietly shrink it.
      expect(LimitInput.megabytesOf(26214400), '25');
      expect(LimitInput.megabytesOf(26214401), '26');
      expect(LimitInput.megabytesOf(1), '1');
    });

    test('unlimited reads back as an empty box', () {
      expect(LimitInput.textOf(0), '');
      expect(LimitInput.textOf(50), '50');
    });

    test('a re-seeded field survives the round trip', () {
      const bytes = 8388608; // 8 MB
      expect(LimitInput.parseMegabytes(LimitInput.megabytesOf(bytes)), bytes);
    });
  });

  group('AttachmentStaging.rejectionFor', () {
    test('a file inside both caps is accepted', () {
      expect(
        AttachmentStaging.rejectionFor(
          name: 'cat.png',
          bytes: 1000,
          maxBytes: 2000,
          alreadyStaged: 0,
        ),
        isNull,
      );
    });

    test('a file exactly at the cap is accepted', () {
      expect(
        AttachmentStaging.rejectionFor(
          name: 'cat.png',
          bytes: 2000,
          maxBytes: 2000,
          alreadyStaged: 0,
        ),
        isNull,
      );
    });

    test('an oversized file is named, measured, and compared', () {
      final rejection = AttachmentStaging.rejectionFor(
        name: 'holiday.mp4',
        bytes: 30 * 1024 * 1024,
        maxBytes: 25 * 1024 * 1024,
        alreadyStaged: 0,
      );
      expect(rejection, contains('holiday.mp4'));
      expect(rejection, contains('30.0 MB'));
      expect(rejection, contains('25.0 MB'));
    });

    test('the count cap is checked before the size cap', () {
      // A full message should say so rather than complain about the file,
      // which would be a confusing thing to fix.
      final rejection = AttachmentStaging.rejectionFor(
        name: 'huge.bin',
        bytes: 99999999,
        maxBytes: 10,
        alreadyStaged: AttachmentStaging.maxPerMessage,
      );
      expect(rejection, contains('per message'));
    });
  });

  group('humanSize', () {
    test('picks a unit a person would use', () {
      expect(humanSize(512), '512 B');
      expect(humanSize(2048), '2 KB');
      expect(humanSize(5 * 1024 * 1024), '5.0 MB');
    });
  });
}
