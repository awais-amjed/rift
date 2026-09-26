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
}
