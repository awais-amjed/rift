import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/classes/seen_key.dart';
import 'package:rift/logic/cubits/app/app_cubit.dart';

/// In-memory stand-in so [AppCubit] (a HydratedCubit) can be built in tests.
class _MemoryStorage implements Storage {
  final Map<String, dynamic> _data = {};

  @override
  dynamic read(String key) => _data[key];

  @override
  Future<void> write(String key, dynamic value) async => _data[key] = value;

  @override
  Future<void> delete(String key) async => _data.remove(key);

  @override
  Future<void> clear() async => _data.clear();

  @override
  Future<void> close() async {}
}

void main() {
  final t1 = DateTime.utc(2026, 10, 2, 9);
  final t2 = DateTime.utc(2026, 10, 2, 10);

  // F-6: a changed key was only flagged inside a profile, and only for
  // somebody you had verified.
  group('SeenKey', () {
    test('the first key seen is a baseline, not a change', () {
      final seen = SeenKey.noting(null, 'A', t1);
      expect(seen.key, 'A');
      expect(seen.changes, isEmpty);
      expect(seen.unacknowledgedChange, isFalse);
    });

    test('the same key again changes nothing', () {
      final before = SeenKey.noting(null, 'A', t1);
      expect(identical(SeenKey.noting(before, 'A', t2), before), isTrue);
    });

    test('a different key is a change nobody has looked at', () {
      final seen = SeenKey.noting(SeenKey.noting(null, 'A', t1), 'B', t2);
      expect(seen.key, 'B');
      expect(seen.changes, [t2]);
      expect(seen.unacknowledgedChange, isTrue);
      expect(seen.acknowledge().unacknowledgedChange, isFalse);
      expect(seen.acknowledge().changes, [t2]);
    });

    test('only the latest changes are kept', () {
      var seen = SeenKey.noting(null, 'k0', t1);
      for (var i = 1; i <= SeenKey.maxChanges + 3; i++) {
        seen = SeenKey.noting(seen, 'k$i', t1.add(Duration(minutes: i)));
      }
      expect(seen.changes, hasLength(SeenKey.maxChanges));
      expect(
        seen.changes.last,
        t1.add(const Duration(minutes: SeenKey.maxChanges + 3)),
      );
    });

    test('round-trips through JSON', () {
      final seen = SeenKey.noting(SeenKey.noting(null, 'A', t1), 'B', t2);
      final back = SeenKey.fromJson(seen.toJson());
      expect(back.key, 'B');
      expect(back.changes, [t2]);
      expect(back.unacknowledgedChange, isTrue);
    });
  });

  group('AppCubit key changes', () {
    // A fresh store each time: the cubit hydrates from it.
    setUp(() => HydratedBloc.storage = _MemoryStorage());

    test('a change is flagged until the code is looked at', () async {
      final app = AppCubit();
      app.noteChatKey('server:u1', 'A');
      app.noteChatKey('server:u1', 'B');
      expect(app.state.seenKeys['server:u1']!.unacknowledgedChange, isTrue);

      app.acknowledgeKeyChange('server:u1');
      expect(app.state.seenKeys['server:u1']!.unacknowledgedChange, isFalse);
      expect(app.state.seenKeys['server:u1']!.changes, hasLength(1));
      await app.close();
    });

    test('marking the new code verified also clears it', () async {
      final app = AppCubit();
      app.noteChatKey('central:u2', 'A');
      app.noteChatKey('central:u2', 'B');
      app.setVerified('central:u2', '123');
      expect(app.state.seenKeys['central:u2']!.unacknowledgedChange, isFalse);
      expect(app.state.verifiedCodes['central:u2'], '123');
      await app.close();
    });

    test('people are kept apart', () async {
      final app = AppCubit();
      app.noteChatKey('server:u1', 'A');
      app.noteChatKey('server:u3', 'A');
      app.noteChatKey('server:u3', 'C');
      expect(app.state.seenKeys['server:u1']!.unacknowledgedChange, isFalse);
      expect(app.state.seenKeys['server:u3']!.unacknowledgedChange, isTrue);
      await app.close();
    });
  });
}
