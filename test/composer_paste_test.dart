import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rift/presentation/common/chat/composer/composer_paste_action.dart';

/// Ctrl+V in the composer goes to the attachment side first, and the field
/// pastes text only when that side declines — so a copied picture is
/// attached, and copied words still paste.
void main() {
  Future<TextEditingController> pumpField(
    WidgetTester tester, {
    required bool takes,
    required List<int> asked,
  }) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => switch (call.method) {
        'Clipboard.getData' => {'text': 'hello'},
        'Clipboard.hasStrings' => {'value': true},
        _ => null,
      },
    );
    final controller = TextEditingController();
    final focus = FocusNode();
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Actions(
            actions: {
              PasteTextIntent: ComposerPasteAction(() async {
                asked.add(1);
                return takes;
              }),
            },
            child: TextField(controller: controller, focusNode: focus),
          ),
        ),
      ),
    );
    focus.requestFocus();
    await tester.pump();
    return controller;
  }

  Future<void> pressPaste(WidgetTester tester) async {
    final modifier = defaultTargetPlatform == TargetPlatform.macOS
        ? LogicalKeyboardKey.metaLeft
        : LogicalKeyboardKey.controlLeft;
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(modifier);
    await tester.pumpAndSettle();
  }

  testWidgets('declined, the field pastes the text', (tester) async {
    final asked = <int>[];
    final controller = await pumpField(tester, takes: false, asked: asked);
    await pressPaste(tester);
    expect(asked, hasLength(1));
    expect(controller.text, 'hello');
  });

  testWidgets('taken, nothing is typed', (tester) async {
    final asked = <int>[];
    final controller = await pumpField(tester, takes: true, asked: asked);
    await pressPaste(tester);
    expect(asked, hasLength(1));
    expect(controller.text, isEmpty);
  });
}
