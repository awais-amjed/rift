import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/fit_aspect.dart';

void main() {
  const bounds = Size(1000, 600);

  test('a wide picture takes the full width', () {
    expect(fitAspect(16 / 9, bounds), const Size(1000, 562.5));
  });

  test('a tall picture takes the full height', () {
    expect(fitAspect(9 / 16, bounds), const Size(337.5, 600));
  });

  test('a picture the shape of the space fills it', () {
    expect(fitAspect(1000 / 600, bounds), bounds);
  });

  test('no space, or no shape, is no box', () {
    expect(fitAspect(16 / 9, const Size(0, 600)), Size.zero);
    expect(fitAspect(16 / 9, const Size(1000, -8)), Size.zero);
    expect(fitAspect(0, bounds), Size.zero);
  });
}
