import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/ptt/release_debounce.dart';

void main() {
  late List<bool> edges;
  late ReleaseDebounce debounce;

  setUp(() {
    edges = [];
    debounce = ReleaseDebounce(onChanged: edges.add);
  });

  test('repeated presses are one press', () {
    debounce.press(0);
    debounce.press(500);
    debounce.press(530);
    expect(edges, [true]);
  });

  test('a release with its own timestamp lets go at once', () {
    debounce.press(0);
    debounce.press(530);
    debounce.release(540);
    expect(edges, [true, false]);
  });

  test('same-instant pairs held down are one press', () {
    fakeAsync((async) {
      for (var t = 0; t < 600; t += 30) {
        debounce.press(t);
        debounce.release(t);
        async.elapse(const Duration(milliseconds: 30));
      }
      expect(edges, [true]);
    });
  });

  test('the last same-instant pair is released after the window', () {
    fakeAsync((async) {
      debounce.press(0);
      debounce.release(1);
      async.elapse(const Duration(milliseconds: 99));
      expect(edges, [true]);
      async.elapse(const Duration(milliseconds: 2));
      expect(edges, [true, false]);
    });
  });

  test('repeats delivered after their release do not reopen the mic', () {
    // A stalled window got a held key's backlog in this order: the release,
    // then the repeats from before it. The mic stayed open for minutes.
    debounce.press(0);
    for (var t = 500; t < 1000; t += 30) {
      debounce.press(t);
    }
    debounce.release(1100);
    for (var t = 1010; t < 1100; t += 30) {
      debounce.press(t);
    }
    expect(edges, [true, false]);
  });

  test('a release older than the latest press is dropped', () {
    debounce.press(0);
    debounce.press(530);
    debounce.release(500);
    expect(edges, [true]);
    debounce.release(600);
    expect(edges, [true, false]);
  });

  test('a press after the release opens again', () {
    debounce.press(0);
    debounce.release(100);
    debounce.press(2000);
    expect(edges, [true, false, true]);
  });

  test('a release without a press does nothing', () {
    debounce.release(10);
    expect(edges, isEmpty);
  });

  test('reset lets go of a held key and cancels a pending release', () {
    fakeAsync((async) {
      debounce.press(0);
      debounce.release(0);
      debounce.reset();
      async.elapse(const Duration(seconds: 1));
      expect(edges, [true, false]);
    });
  });
}
