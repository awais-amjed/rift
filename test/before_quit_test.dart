import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/before_quit.dart';

void main() {
  group('BeforeQuit', () {
    test('runs every task, and waits for them', () async {
      final done = <String>[];
      Future<void> a() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        done.add('a');
      }

      Future<void> b() async => done.add('b');
      BeforeQuit.instance
        ..add(a)
        ..add(b);
      addTearDown(() {
        BeforeQuit.instance
          ..remove(a)
          ..remove(b);
      });

      await BeforeQuit.instance.run();
      expect(done, unorderedEquals(['a', 'b']));
    });

    test('a task that throws does not stop the others or the quit', () async {
      var ran = false;
      Future<void> bad() async => throw StateError('no');
      Future<void> good() async => ran = true;
      BeforeQuit.instance
        ..add(bad)
        ..add(good);
      addTearDown(() {
        BeforeQuit.instance
          ..remove(bad)
          ..remove(good);
      });

      await BeforeQuit.instance.run();
      expect(ran, isTrue);
    });

    test('a task that never finishes is given up on at the limit', () async {
      final never = Completer<void>();
      Future<void> hang() => never.future;
      BeforeQuit.instance.add(hang);
      addTearDown(() => BeforeQuit.instance.remove(hang));

      final watch = Stopwatch()..start();
      await BeforeQuit.instance.run(limit: const Duration(milliseconds: 50));
      expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('a removed task does not run', () async {
      var ran = false;
      Future<void> task() async => ran = true;
      BeforeQuit.instance
        ..add(task)
        ..remove(task);

      await BeforeQuit.instance.run();
      expect(ran, isFalse);
    });
  });
}
