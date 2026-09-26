import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/call_start_times.dart';

void main() {
  final t0 = DateTime(2026, 9, 26, 12);
  final later = t0.add(const Duration(minutes: 5));
  final server = t0.subtract(const Duration(hours: 1));

  test('a channel that fills is timed from when it was seen filling', () {
    final times = const CallStartTimes().update({'a'}, t0);
    expect(times.started, {'a': t0});
    // And keeps that start while it stays occupied.
    expect(times.update({'a'}, later).started, {'a': t0});
  });

  test("the server's start wins for a call that began before we looked", () {
    final times = const CallStartTimes().update({'a'}, t0).withServer({
      'a': server,
    }, t0);
    expect(times.started['a'], server);
  });

  test('a server start waits for presence to show the channel occupied', () {
    final times = const CallStartTimes().withServer({'a': server}, t0);
    expect(times.started, isEmpty);
    expect(times.update({'a'}, later).started['a'], server);
  });

  test('an empty channel forgets, so the next call starts from zero', () {
    final times = const CallStartTimes()
        .update({'a'}, t0)
        .withServer({'a': server}, t0)
        .update({}, later);
    expect(times.started, isEmpty);
    final again = later.add(const Duration(minutes: 1));
    expect(times.update({'a'}, again).started['a'], again);
  });

  // Seen live: an app killed mid-call was still in LiveKit's room when its
  // next session asked for the roster, and the start it got was handed to a
  // call that began minutes later.
  test('a start presence never confirms is dropped after the grace', () {
    final times = const CallStartTimes().withServer({'a': server}, t0);
    final afterGrace = t0.add(
      CallStartTimes.grace + const Duration(seconds: 1),
    );
    final waited = times.update({}, afterGrace);
    expect(waited.fromServer, isEmpty);
    expect(waited.update({'a'}, later).started['a'], later);
  });

  test(
    'within the grace, presence catching up still gets the server start',
    () {
      final times = const CallStartTimes().withServer({'a': server}, t0);
      final soon = t0.add(const Duration(seconds: 3));
      expect(times.update({'a'}, soon).started['a'], server);
    },
  );
}
