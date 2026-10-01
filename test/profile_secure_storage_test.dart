import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/dpapi_codec.dart';
import 'package:rift/logic/services/profile_secure_storage.dart';

/// Stands in for DPAPI off Windows: reversible, and refuses what it did not
/// seal, the way DPAPI refuses another user's bytes.
class _FakeCodec implements SecretCodec {
  static const _mark = 0x5A;

  @override
  Uint8List seal(Uint8List plain) => Uint8List.fromList([_mark, ...plain]);

  @override
  Uint8List open(Uint8List sealed) {
    if (sealed.isEmpty || sealed.first != _mark) {
      throw const FormatException('not sealed here');
    }
    return Uint8List.sublistView(sealed, 1);
  }
}

/// Windows kept every profile's secrets in one file in Roaming AppData, the
/// folder a domain copies to every PC the person signs in to. Each profile now
/// has a file of its own under Local AppData, and takes its keys out of the
/// old one the first time it runs.
void main() {
  late Directory dir;
  final codec = _FakeCodec();
  const options = <String, String>{};

  setUp(() async => dir = await Directory.systemTemp.createTemp('secure_'));
  tearDown(() => dir.delete(recursive: true));

  File local(String profile) =>
      File('${dir.path}/local/rift_$profile/secure_storage.dat');
  File roamingFile() => File('${dir.path}/roaming/flutter_secure_storage.dat');

  Future<void> seedRoaming(Map<String, String> values) async {
    await roamingFile().parent.create(recursive: true);
    await roamingFile().writeAsBytes(
      codec.seal(utf8.encode(jsonEncode(values))),
    );
  }

  Map<String, String> readRoaming() => Map<String, String>.from(
    jsonDecode(utf8.decode(codec.open(roamingFile().readAsBytesSync()))) as Map,
  );

  ProfileSecureStorage storage(String profile) => ProfileSecureStorage(
    local(profile),
    codec: codec,
    legacyFile: roamingFile(),
    legacyKeys: {'$profile.master_seed', '$profile.joined_servers'},
  );

  test('values are kept, read back after a restart, and removed', () async {
    final a = storage('wa');
    await a.write(key: 'wa.master_seed', value: 'seed-a', options: options);
    expect(local('wa').existsSync(), isTrue);
    expect(codec.open(local('wa').readAsBytesSync()), isNotEmpty);

    final reopened = storage('wa');
    expect(
      await reopened.read(key: 'wa.master_seed', options: options),
      'seed-a',
    );
    await reopened.delete(key: 'wa.master_seed', options: options);
    expect(
      await storage('wa').containsKey(key: 'wa.master_seed', options: options),
      isFalse,
    );
  });

  test(
    'each profile takes only its own keys out of the roaming file',
    () async {
      await seedRoaming({
        'wa.master_seed': 'seed-a',
        'wa.joined_servers': '[]',
        'wb.master_seed': 'seed-b',
      });

      expect(
        await storage('wa').read(key: 'wa.master_seed', options: options),
        'seed-a',
      );
      expect(readRoaming(), {'wb.master_seed': 'seed-b'});

      expect(
        await storage('wb').read(key: 'wb.master_seed', options: options),
        'seed-b',
      );
      expect(
        roamingFile().existsSync(),
        isFalse,
        reason: 'nobody\'s keys are left',
      );
      expect(await storage('wa').readAll(options: options), {
        'wa.master_seed': 'seed-a',
        'wa.joined_servers': '[]',
      });
    },
  );

  test(
    'a copy of its own wins over what is left in the roaming file',
    () async {
      // Another profile rewriting the roaming file at the same moment can put a
      // moved key back. It is stale; the next launch takes it out again.
      final a = storage('wa');
      await a.write(key: 'wa.master_seed', value: 'current', options: options);
      await seedRoaming({
        'wa.master_seed': 'stale',
        'wb.master_seed': 'seed-b',
      });

      expect(
        await storage('wa').read(key: 'wa.master_seed', options: options),
        'current',
      );
      expect(readRoaming(), {'wb.master_seed': 'seed-b'});
    },
  );

  test('an unreadable file of its own is set aside, never deleted', () async {
    await local('wa').parent.create(recursive: true);
    await local('wa').writeAsBytes([1, 2, 3]);

    expect(
      await storage('wa').read(key: 'wa.master_seed', options: options),
      isNull,
    );
    final setAside = File('${local('wa').path}.unreadable');
    expect(setAside.readAsBytesSync(), [1, 2, 3]);
  });

  test('an unreadable roaming file is left as it is', () async {
    await roamingFile().parent.create(recursive: true);
    await roamingFile().writeAsBytes([9, 9, 9]);

    expect(
      await storage('wa').read(key: 'wa.master_seed', options: options),
      isNull,
    );
    expect(roamingFile().readAsBytesSync(), [9, 9, 9]);
  });

  test('DPAPI opens what it sealed, and the sealed bytes hide the text', () {
    const codec = DpapiCodec();
    final plain = Uint8List.fromList(utf8.encode('{"wa.master_seed":"x"}'));
    final sealed = codec.seal(plain);
    expect(
      utf8.decode(sealed, allowMalformed: true),
      isNot(contains('master_seed')),
    );
    expect(codec.open(sealed), plain);
    expect(
      () => codec.open(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
  }, skip: Platform.isWindows ? false : 'DPAPI is Windows only');
}
