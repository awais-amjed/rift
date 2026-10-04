import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/logic/cubits/app/app_cubit.dart';
import 'package:rift/logic/cubits/server/server_cubit.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/logic/cubits/token/token_cubit.dart';
import 'package:rift/logic/services/hydrated_keys.dart';

import 'helpers/memory_storage.dart';

/// One Hive frame: length, a string key, a value, a checksum. The value and
/// checksum are filler — the walk reads only lengths and keys.
List<int> _frame(String key, {int valueBytes = 5}) {
  final keyBytes = utf8.encode(key);
  final length = 4 + 2 + keyBytes.length + valueBytes + 4;
  final out = ByteData(length)..setUint32(0, length, Endian.little);
  final bytes = out.buffer.asUint8List()
    ..[4] = 1
    ..[5] = keyBytes.length
    ..setRange(6, 6 + keyBytes.length, keyBytes);
  return bytes;
}

/// The same with an integer key, which the walk steps over.
List<int> _intFrame() {
  const length = 4 + 1 + 4 + 3 + 4;
  return (ByteData(length)..setUint32(0, length, Endian.little)).buffer
      .asUint8List()
    ..[4] = 0;
}

void main() {
  setUpAll(() => HydratedBloc.storage = MemoryStorage());

  group('the names state is saved under', () {
    // Obfuscated and minified builds name a class differently every build;
    // these must not, and must stay what unobfuscated builds always used.
    test('are fixed, and the class names Linux builds have used', () {
      expect(AppCubit().storagePrefix, 'AppCubit');
      expect(ThemeCubit().storagePrefix, 'ThemeCubit');
      expect(TokenCubit().storagePrefix, 'TokenCubit');
      expect(HydratedKeys.server, 'ServerCubit');
    });
  });

  group('recognising a record saved under an old name', () {
    test('knows each state by what its own toJson writes', () {
      expect(
        HydratedKeyRecovery.kindOf(const AppState().toJson()),
        HydratedKeys.app,
      );
      expect(
        HydratedKeyRecovery.kindOf(const ServerState().toJson()),
        HydratedKeys.server,
      );
      expect(
        HydratedKeyRecovery.kindOf(ThemeState().toJson()),
        HydratedKeys.theme,
      );
      expect(
        HydratedKeyRecovery.kindOf(
          TokenCubit().toJson(const TokenState()),
        ),
        HydratedKeys.token,
      );
    });

    test('ignores anything else', () {
      expect(HydratedKeyRecovery.kindOf(null), isNull);
      expect(HydratedKeyRecovery.kindOf('servers'), isNull);
      expect(HydratedKeyRecovery.kindOf({'tokens': {}, 'x': 1}), isNull);
    });
  });

  group('choosing what to carry over', () {
    final oldServers = {'servers': [], 'orderClock': 1};
    final newServers = {'servers': [{}], 'orderClock': 2};

    test('takes the most recently written of several', () {
      final plan = HydratedKeyRecovery.plan(
        {'Sjb': newServers, 'Ujb': oldServers, 'Abc': const {'tokens': {}}},
        ['Ujb', 'Abc', 'Sjb'],
      );
      expect(plan, {HydratedKeys.server: 'Sjb', HydratedKeys.token: 'Abc'});
    });

    test('leaves a name alone once something is saved under it', () {
      final plan = HydratedKeyRecovery.plan(
        {HydratedKeys.server: oldServers, 'Sjb': newServers},
        ['ServerCubit', 'Sjb'],
      );
      expect(plan, isEmpty);
    });

    test('takes a key the file does not list as the oldest', () {
      final plan = HydratedKeyRecovery.plan(
        {'Gone': newServers, 'Ujb': oldServers},
        ['Ujb'],
      );
      expect(plan, {HydratedKeys.server: 'Ujb'});
    });

    test('with no order known, still takes one', () {
      final plan = HydratedKeyRecovery.plan({'Sjb': newServers}, const []);
      expect(plan, {HydratedKeys.server: 'Sjb'});
    });
  });

  group('reading the order keys were written in', () {
    test('a key counts from its last write', () {
      final bytes = Uint8List.fromList([
        ..._frame('Sjb'),
        ..._frame('Ujb'),
        ..._intFrame(),
        ..._frame('Sjb', valueBytes: 40),
      ]);
      expect(HydratedKeyRecovery.keysInWriteOrder(bytes), ['Ujb', 'Sjb']);
    });

    test('a torn last frame ends the walk, keeping what came before', () {
      final whole = [..._frame('Sjb'), ..._frame('Ujb')];
      final torn = _frame('Abc').sublist(0, 7);
      expect(
        HydratedKeyRecovery.keysInWriteOrder(
          Uint8List.fromList([...whole, ...torn]),
        ),
        ['Sjb', 'Ujb'],
      );
    });

    test('an empty file has no keys', () {
      expect(HydratedKeyRecovery.keysInWriteOrder(Uint8List(0)), isEmpty);
    });
  });
}
