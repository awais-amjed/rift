import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/preferences_file.dart';

/// A shared_preferences file a power cut zeroed stopped Rift starting on
/// Windows, every launch, until the file was moved by hand.
void main() {
  late Directory dir;
  late File file;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('preferences_');
    file = File('${dir.path}/shared_preferences.json');
  });

  tearDown(() => dir.delete(recursive: true));

  File setAside() => File('${file.path}.unreadable');

  test('a zeroed file is set aside, bytes kept', () async {
    await file.writeAsBytes(List.filled(2048, 0));
    expect(await PreferencesFile.check(file), isTrue);
    expect(file.existsSync(), isFalse);
    expect(setAside().lengthSync(), 2048);
  });

  test('bytes that are not UTF-8 are set aside', () async {
    await file.writeAsBytes([0xFF, 0xFE, 0x7B]);
    expect(await PreferencesFile.check(file), isTrue);
    expect(file.existsSync(), isFalse);
  });

  test('half a file is set aside', () async {
    await file.writeAsString('{"flutter.sb-api-auth-token":"{\\"acc');
    expect(await PreferencesFile.check(file), isTrue);
  });

  test('an earlier unreadable copy is replaced', () async {
    await setAside().writeAsString('older');
    await file.writeAsBytes(List.filled(16, 0));
    expect(await PreferencesFile.check(file), isTrue);
    expect(setAside().lengthSync(), 16);
  });

  test('a good file, an empty one and none at all are left alone', () async {
    expect(await PreferencesFile.check(file), isFalse);
    await file.writeAsString('');
    expect(await PreferencesFile.check(file), isFalse);
    await file.writeAsString('{"flutter.a":"b"}');
    expect(await PreferencesFile.check(file), isFalse);
    expect(file.readAsStringSync(), '{"flutter.a":"b"}');
    expect(setAside().existsSync(), isFalse);
  });
}
