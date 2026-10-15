import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rift/presentation/common/rounded_picture.dart';

/// A picture avatar is the fill of a rounded square, never a square cut by
/// a clip: on some Linux drivers the clip came and went between frames, and
/// the avatars flickered square (see [RoundedPicture]).
void main() {
  testWidgets('paints the picture as a rounded fill, with no clip', (
    tester,
  ) async {
    final png = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(
        const Rect.fromLTWH(0, 0, 4, 2),
        Paint()..color = const Color(0xFF22AA44),
      );
      final image = await recorder.endRecording().toImage(4, 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });

    await tester.pumpWidget(
      Center(child: RoundedPicture(bytes: png!, size: 28, radius: 7.84)),
    );
    // Decoding happens off the test's fake clock.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();

    expect(find.byType(ClipRRect), findsNothing);
    expect(
      find.descendant(
        of: find.byType(RoundedPicture),
        matching: find.byType(CustomPaint),
      ),
      paints..rrect(
        rrect: RRect.fromRectAndRadius(
          const Rect.fromLTWH(0, 0, 28, 28),
          const Radius.circular(7.84),
        ),
      ),
    );
  });
}
