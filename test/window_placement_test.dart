import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/window_placement.dart';

void main() {
  // A 1920×1080 screen with a 48 px taskbar, at 100 % and at 150 % (the same
  // screen in logical pixels).
  const at100 = Rect.fromLTWH(0, 0, 1920, 1032);
  const at150 = Rect.fromLTWH(0, 0, 1280, 688);

  test('a window that fits stays exactly where it was', () {
    final r = fitWindowToScreens(
      size: const Size(1280, 720),
      position: const Offset(10, 10),
      workAreas: const [at100],
      primary: at100,
    );
    expect(r.size, const Size(1280, 720));
    expect(r.position, const Offset(10, 10));
  });

  test('after the scale goes up, the window shrinks onto the screen', () {
    // Seen on Windows: saved at 1280×720 at 100 %, reopened at 150 % it
    // covered the whole screen from (15,15), under the taskbar.
    final r = fitWindowToScreens(
      size: const Size(1280, 720),
      position: const Offset(10, 10),
      workAreas: const [at150],
      primary: at150,
    );
    expect(r.size, const Size(1280, 688));
    expect(r.position, Offset.zero);
  });

  test('a window hanging off an edge is moved back, not shrunk', () {
    final r = fitWindowToScreens(
      size: const Size(800, 600),
      position: const Offset(1500, 700),
      workAreas: const [at100],
      primary: at100,
    );
    expect(r.size, const Size(800, 600));
    expect(r.position, const Offset(1120, 432));
  });

  test('a window on a monitor that is gone comes back to the primary', () {
    final r = fitWindowToScreens(
      size: const Size(1280, 720),
      position: const Offset(2500, 100),
      workAreas: const [at100],
      primary: at100,
    );
    expect(r.size, const Size(1280, 720));
    expect(r.position, const Offset(640, 100));
  });

  test('a window spanning two monitors goes to the one holding most of it', () {
    const right = Rect.fromLTWH(1920, 0, 1280, 1000);
    final r = fitWindowToScreens(
      size: const Size(1000, 600),
      position: const Offset(1700, 50),
      workAreas: const [at100, right],
      primary: at100,
    );
    expect(r.size, const Size(1000, 600));
    expect(r.position, const Offset(1920, 50));
  });

  test('a monitor left of the primary (negative x) is a real place', () {
    const left = Rect.fromLTWH(-1920, 0, 1920, 1040);
    final r = fitWindowToScreens(
      size: const Size(1280, 720),
      position: const Offset(-1500, 100),
      workAreas: const [left, at100],
      primary: at100,
    );
    expect(r.position, const Offset(-1500, 100));
  });

  test('nothing saved yet: the size is fitted and the platform places it', () {
    final r = fitWindowToScreens(
      size: const Size(1280, 720),
      position: null,
      workAreas: const [at150],
      primary: at150,
    );
    expect(r.size, const Size(1280, 688));
    expect(r.position, isNull);
  });
}
