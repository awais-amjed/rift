import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/call_steps.dart';

/// Joining and leaving a call each wait on the network, and a press of
/// either used to run beside one still waiting. Leave while "Connecting…"
/// found no room to close, and the join then connected anyway, into a call
/// with no Leave button; a quick switch left the first room connected under
/// the second channel's name.
void main() {
  test('a step waits for the one before it to finish', () async {
    final steps = CallSteps();
    final order = <String>[];
    final first = Completer<void>();

    final a = steps.run(() async {
      order.add('a starts');
      await first.future;
      order.add('a ends');
    });
    final b = steps.run(() async => order.add('b'));
    await Future<void>.delayed(Duration.zero);
    expect(order, ['a starts']);

    first.complete();
    await Future.wait([a, b]);
    expect(order, ['a starts', 'a ends', 'b']);
  });

  test('a later press makes a join still waiting stale', () async {
    final steps = CallSteps();
    final token = Completer<void>();
    bool? joinStillCurrent;

    final join = steps.begin();
    final joining = steps.run(() async {
      await token.future;
      joinStillCurrent = steps.isCurrent(join);
    });

    // Leave, pressed while the join waits on its token.
    final leave = steps.begin();
    token.complete();
    await joining;

    expect(joinStillCurrent, isFalse);
    expect(steps.isCurrent(leave), isTrue);
  });

  test('a step that throws does not stop the next', () async {
    final steps = CallSteps();
    var ran = false;
    await steps.run(() async => throw StateError('boom'));
    await steps.run(() async => ran = true);
    expect(ran, isTrue);
  });
}
