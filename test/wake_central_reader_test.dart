import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/push_wake/wake_central_reader.dart';
import 'package:rift/logic/services/push_wake/wake_marks.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A wake with no usable central session: silent for a ring a server
/// forwarded, and "could not read it" for central's own, so a Rift DM that
/// arrived an hour after Rift was last open is not passed over in silence.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final seed = Uint8List(32);

  test(
    'a server\'s ring with no central session says nothing about central',
    () async {
      final harvest = await WakeCentralReader().read(
        seed,
        WakeMarks({}),
        storageSuffix: '',
      );
      expect(harvest.items, isEmpty);
      expect(harvest.failed, isFalse);
    },
  );

  test('central\'s own ring with no session is a message not read', () async {
    final harvest = await WakeCentralReader().read(
      seed,
      WakeMarks({}),
      storageSuffix: '',
      aboutCentral: true,
    );
    expect(harvest.items, isEmpty);
    expect(harvest.failed, isTrue);
  });
}
