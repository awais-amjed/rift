import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/coalesced_refresh.dart';

/// Collapsing the several ways a client is told the same thing.
///
/// The cases that matter are the ones where collapsing too hard is wrong: a
/// caller must never be handed an answer that was already in flight before
/// they asked, because that is how a client ends up one change behind and
/// stays there until something unrelated happens to ask again.
void main() {
  /// A refresh the test completes by hand, counting how often it ran.
  ({
    CoalescedRefresh<int> refresh,
    List<Completer<int>> runs,
  })
  subject() {
    final runs = <Completer<int>>[];
    return (
      refresh: CoalescedRefresh<int>(() {
        final completer = Completer<int>();
        runs.add(completer);
        return completer.future;
      }),
      runs: runs,
    );
  }

  test('one caller is one read', () async {
    final s = subject();
    final answer = s.refresh();
    expect(s.runs, hasLength(1));

    s.runs.first.complete(7);
    expect(await answer, 7);
    expect(s.refresh.isRunning, isFalse);
  });

  test('callers arriving mid-flight share one further read', () async {
    final s = subject();
    final first = s.refresh();
    final second = s.refresh();
    final third = s.refresh();

    // Two, not four: the three latecomers share a turn, and the running read
    // is not one of them.
    expect(s.runs, hasLength(1));
    s.runs[0].complete(1);
    await first;
    await pumpEventQueue();

    expect(s.runs, hasLength(2));
    s.runs[1].complete(2);
    expect(await second, 2);
    expect(await third, 2);
  });

  // The whole reason this is not "drop it if one is in flight". The read
  // already running was asked for before the second caller had a reason to
  // ask, so its answer may predate the change they are asking about.
  test('a latecomer never receives the answer that was already in flight',
      () async {
    final s = subject();
    final first = s.refresh();
    final second = s.refresh();

    s.runs[0].complete(1);
    expect(await first, 1);
    await pumpEventQueue();
    s.runs[1].complete(2);

    expect(await second, isNot(1));
  });

  test('arriving during the second read earns a third', () async {
    final s = subject();
    final first = s.refresh();
    final queued = s.refresh();
    s.runs[0].complete(1);
    await first;
    await pumpEventQueue();

    // The queued read is running now. Somebody asking at this moment is
    // asking about something it may not have seen.
    final late_ = s.refresh();
    expect(s.runs, hasLength(2));
    s.runs[1].complete(2);
    expect(await queued, 2);
    await pumpEventQueue();

    expect(s.runs, hasLength(3));
    s.runs[2].complete(3);
    expect(await late_, 3);
  });

  test('callers one after another each get their own read', () async {
    final s = subject();
    for (var i = 0; i < 3; i++) {
      final answer = s.refresh();
      s.runs[i].complete(i);
      expect(await answer, i);
    }
    expect(s.runs, hasLength(3));
  });

  // The wedge this nearly shipped with: a caller queued behind a read that
  // then failed. Chained with a plain `then`, their turn never comes, the
  // queue slot stays pointing at the failure, and every later caller is
  // handed it — the refresh is dead for the life of the cubit.
  test('a latecomer still gets a read when the one ahead of them fails',
      () async {
    final s = subject();
    final first = s.refresh();
    final second = s.refresh();

    s.runs[0].completeError(StateError('offline'));
    await expectLater(first, throwsStateError);
    await pumpEventQueue();

    expect(s.runs, hasLength(2), reason: 'the queued read never ran');
    s.runs[1].complete(9);
    expect(await second, 9);

    // And the slot is free again rather than holding the dead future.
    await pumpEventQueue();
    final third = s.refresh();
    expect(s.runs, hasLength(3));
    s.runs[2].complete(10);
    expect(await third, 10);
  });

  // A refresh that throws must not wedge the next one behind a future that
  // will never complete.
  test('a failed read leaves the next caller a clean slate', () async {
    final s = subject();
    final first = s.refresh();
    s.runs[0].completeError(StateError('offline'));
    await expectLater(first, throwsStateError);
    await pumpEventQueue();

    expect(s.refresh.isRunning, isFalse);
    final second = s.refresh();
    expect(s.runs, hasLength(2));
    s.runs[1].complete(5);
    expect(await second, 5);
  });
}
