import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/device_id.dart';

/// A restarted app has to join a call as the same device, or LiveKit keeps
/// the dead connection beside the new one and everybody sees two of you.
void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('device_id_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('the first run saves its id, and the next run reads it back', () async {
    final file = File('${dir.path}/profile/device_id');
    final first = DeviceId.current;
    await DeviceId.loadFrom(file);
    expect(file.readAsStringSync(), first);

    // Another install's id on disk is this install's from now on.
    file.writeAsStringSync('0123abcd');
    await DeviceId.loadFrom(file);
    expect(DeviceId.current, '0123abcd');
  });

  test('a file that is not an id is replaced, not trusted', () async {
    final file = File('${dir.path}/device_id')..writeAsStringSync('../../x y');
    final before = DeviceId.current;
    await DeviceId.loadFrom(file);
    expect(DeviceId.current, before);
    expect(file.readAsStringSync(), before);
  });
}
