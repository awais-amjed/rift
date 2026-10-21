import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/steady_clock.dart';

void main() {
  test('runs forward with time passing', () async {
    final before = SteadyClock.now();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(
      SteadyClock.now().difference(before),
      greaterThanOrEqualTo(const Duration(milliseconds: 20)),
    );
  });

  test('a time from elsewhere keeps its age', () {
    final started = SteadyClock.fromWall(
      DateTime.now().subtract(const Duration(hours: 2)),
    );
    final age = SteadyClock.now().difference(started);
    expect(age, greaterThanOrEqualTo(const Duration(hours: 2)));
    expect(age, lessThan(const Duration(hours: 2, seconds: 1)));
  });
}
