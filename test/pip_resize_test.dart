import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/enums/stream_pip_corner.dart';
import 'package:rift/logic/services/pip_resize.dart';

double grown(Offset moved, StreamPipCorner corner) =>
    pipResizedWidth(from: 300, moved: moved, corner: corner, aspect: 2);

void main() {
  test('pulled away from its corner, it grows by the pull', () {
    expect(grown(const Offset(-40, 0), StreamPipCorner.bottomRight), 340);
    expect(grown(const Offset(40, 0), StreamPipCorner.topLeft), 340);
    expect(grown(const Offset(0, 20), StreamPipCorner.topLeft), 340);
  });

  test('a drift back across a pull down costs nothing', () {
    expect(grown(const Offset(-5, 30), StreamPipCorner.topRight), 360);
  });

  test('pushed toward its corner, it shrinks', () {
    expect(grown(const Offset(40, 0), StreamPipCorner.bottomRight), 260);
    expect(grown(const Offset(40, 10), StreamPipCorner.bottomRight), 260);
  });
}
