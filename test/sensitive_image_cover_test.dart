import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rift/data/enums/sensitive_content_mode.dart';
import 'package:rift/presentation/common/chat/attachments/sensitive_image_cover.dart';

void main() {
  setUp(SensitiveImageCover.resetReveals);

  Widget cover(SensitiveContentMode mode, {String id = 'a1'}) => MaterialApp(
    home: Scaffold(
      body: SensitiveImageCover(
        attachmentId: id,
        mode: mode,
        child: const SizedBox(width: 120, height: 80, key: Key('picture')),
      ),
    ),
  );

  testWidgets('blur mode: covered until tapped, then shown', (tester) async {
    await tester.pumpWidget(cover(SensitiveContentMode.blur));
    expect(find.text('Sensitive image'), findsOneWidget);
    expect(find.text('Press to show'), findsOneWidget);

    await tester.tap(find.text('Sensitive image'));
    await tester.pump();
    expect(find.text('Sensitive image'), findsNothing);
    expect(find.byKey(const Key('picture')), findsOneWidget);
  });

  testWidgets('a reveal is remembered for the picture, not the widget', (
    tester,
  ) async {
    await tester.pumpWidget(cover(SensitiveContentMode.blur));
    await tester.tap(find.text('Sensitive image'));
    await tester.pump();

    // Rebuilt from scratch, as a scroll would: still revealed.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(cover(SensitiveContentMode.blur));
    expect(find.text('Sensitive image'), findsNothing);

    // A different picture is its own decision.
    await tester.pumpWidget(cover(SensitiveContentMode.blur, id: 'a2'));
    expect(find.text('Sensitive image'), findsOneWidget);
  });

  testWidgets('hide mode: no way through here', (tester) async {
    await tester.pumpWidget(cover(SensitiveContentMode.hide));
    expect(find.text('Hidden by your settings'), findsOneWidget);

    await tester.tap(find.text('Sensitive image'));
    await tester.pump();
    expect(find.text('Sensitive image'), findsOneWidget);
  });

  testWidgets('a video names itself and tells its card when lifted', (
    tester,
  ) async {
    var told = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SensitiveImageCover(
            attachmentId: 'v1',
            mode: SensitiveContentMode.blur,
            label: 'Sensitive video',
            onReveal: () => told++,
            child: const SizedBox(width: 120, height: 80),
          ),
        ),
      ),
    );
    expect(find.text('Sensitive video'), findsOneWidget);
    expect(SensitiveImageCover.isRevealed('v1'), isFalse);

    await tester.tap(find.text('Sensitive video'));
    await tester.pump();
    expect(told, 1);
    expect(SensitiveImageCover.isRevealed('v1'), isTrue);
  });
}
