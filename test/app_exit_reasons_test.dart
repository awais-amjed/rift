import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/app_exit_reasons.dart';

/// Android's record of how a run ended, in words a report's reader can use
/// without looking the numbers up.
void main() {
  test('a run killed for memory in its call service says so', () {
    expect(
      AppExitReasons.describe({
        'timestamp': DateTime.utc(
          2026,
          10,
          23,
          19,
          3,
          59,
        ).millisecondsSinceEpoch,
        'pid': 4321,
        'process': 'com.codingfries.rift',
        'reason': 3,
        'status': 0,
        'importance': 125,
        'pssKb': 312 * 1024,
        'description': 'lmk',
      }),
      'run 4321 (com.codingfries.rift) ended 2026-10-23T19:03:59.000Z: '
      'killed for low memory, in a foreground service, 312 MB in use – lmk',
    );
  });

  test(
    'a native crash names its signal, and an empty description is left out',
    () {
      expect(
        AppExitReasons.describe({
          'timestamp': 0,
          'pid': 7,
          'process': 'com.codingfries.rift',
          'reason': 5,
          'status': 11,
          'importance': 100,
          'pssKb': 0,
          'description': '',
        }),
        'run 7 (com.codingfries.rift) ended 1970-01-01T00:00:00.000Z: '
        'crashed in native code (signal 11), on screen',
      );
    },
  );

  test('a reason Android adds later still reads', () {
    expect(
      AppExitReasons.describe({'reason': 99, 'importance': 1000}),
      contains('ended for an unknown reason (99), importance 1000'),
    );
  });
}
