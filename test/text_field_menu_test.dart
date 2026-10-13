import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/context_menu/context_menu_item.dart';
import 'package:rift/presentation/common/context_menu/text_field_context_menu.dart';

import 'helpers/memory_storage.dart';

/// Right-clicking a text field opens Rift's menu, whatever is in the field
/// or on the clipboard. Flutter's own listed only what applied, so an empty
/// field with a picture on the clipboard opened nothing at all.
void main() {
  setUpAll(() => HydratedBloc.storage = MemoryStorage());

  test('every text field in lib/ has the app\'s menu', () {
    final call = RegExp(
      r'^(?!\s*//).*\b(TextField|TextFormField|SelectableText)\(',
      multiLine: true,
    );
    final missing = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final source = file.readAsStringSync();
      for (final match in call.allMatches(source)) {
        if (!source
            .substring(match.end)
            .trimLeft()
            .startsWith('contextMenuBuilder:')) {
          final line =
              '\n'.allMatches(source.substring(0, match.end)).length + 1;
          missing.add('${file.path}:$line');
        }
      }
    }
    expect(missing, isEmpty);
  });

  String? clipboard;
  setUp(() => clipboard = null);

  Future<void> host(WidgetTester tester, Widget field) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => switch (call.method) {
        'Clipboard.getData' => clipboard == null ? null : {'text': clipboard},
        'Clipboard.hasStrings' => {'value': clipboard != null},
        'Clipboard.setData' => () {
          clipboard = (call.arguments as Map)['text'] as String?;
        }(),
        _ => null,
      },
    );
    return tester.pumpWidget(
      BlocProvider<ThemeCubit>(
        create: (_) => ThemeCubit(),
        child: MaterialApp(
          home: Material(
            child: Center(child: SizedBox(width: 300, child: field)),
          ),
        ),
      ),
    );
  }

  Future<void> rightClick(WidgetTester tester, Finder target) async {
    final gesture = await tester.startGesture(
      tester.getCenter(target),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await gesture.up();
    await tester.pumpAndSettle();
  }

  /// The menu's rows by label, null where the row is greyed.
  Map<String, VoidCallback?> rows(WidgetTester tester) => {
    for (final item in tester.widgetList<ContextMenuItem>(
      find.byType(ContextMenuItem),
    ))
      item.label: item.onTap,
  };

  testWidgets('an empty field with nothing to paste still opens it', (
    tester,
  ) async {
    await host(
      tester,
      const TextField(contextMenuBuilder: TextFieldContextMenu.builder),
    );
    await rightClick(tester, find.byType(TextField));
    final menu = rows(tester);
    expect(menu.keys, ['Cut', 'Copy', 'Paste', 'Select all']);
    expect(menu['Cut'], isNull);
    expect(menu['Copy'], isNull);
    expect(menu['Paste'], isNotNull);
    expect(menu['Select all'], isNull);
  });

  testWidgets('Paste pastes, Select all then Copy copies', (tester) async {
    final controller = TextEditingController();
    clipboard = 'hello';
    await host(
      tester,
      TextField(
        controller: controller,
        contextMenuBuilder: TextFieldContextMenu.builder,
      ),
    );
    await rightClick(tester, find.byType(TextField));
    await tester.tap(find.text('Paste'));
    await tester.pumpAndSettle();
    expect(controller.text, 'hello');
    expect(find.byType(ContextMenuItem), findsNothing);

    await rightClick(tester, find.byType(TextField));
    await tester.tap(find.text('Select all'));
    await tester.pumpAndSettle();
    await rightClick(tester, find.byType(TextField));
    expect(rows(tester)['Copy'], isNotNull);
    clipboard = null;
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(clipboard, 'hello');
  });

  testWidgets('the composer\'s Paste goes to its attachments first', (
    tester,
  ) async {
    final controller = TextEditingController();
    clipboard = 'words';
    var asked = 0;
    await host(
      tester,
      TextField(
        controller: controller,
        contextMenuBuilder: TextFieldContextMenu.pasting(() async {
          asked++;
          return true;
        }),
      ),
    );
    await rightClick(tester, find.byType(TextField));
    await tester.tap(find.text('Paste'));
    await tester.pumpAndSettle();
    expect(asked, 1);
    expect(controller.text, isEmpty);
  });

  testWidgets('a click elsewhere closes it, and so does Escape', (
    tester,
  ) async {
    await host(
      tester,
      const TextField(contextMenuBuilder: TextFieldContextMenu.builder),
    );
    await rightClick(tester, find.byType(TextField));
    expect(find.byType(ContextMenuItem), findsWidgets);
    await tester.tapAt(const Offset(5, 5), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(find.byType(ContextMenuItem), findsNothing);

    await rightClick(tester, find.byType(TextField));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(ContextMenuItem), findsNothing);
  });

  testWidgets('text that cannot be typed into offers no Cut or Paste', (
    tester,
  ) async {
    await host(
      tester,
      const SelectableText(
        'secret',
        contextMenuBuilder: TextFieldContextMenu.builder,
      ),
    );
    await rightClick(tester, find.byType(SelectableText));
    expect(rows(tester).keys, ['Copy', 'Select all']);
  });
}
