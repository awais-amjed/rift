import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/app_text_field.dart';
import 'package:rift/presentation/common/chat/composer/chat_composer.dart';
import 'package:rift/presentation/common/search_dropdown_field.dart';
import 'package:rift/presentation/common/tap_to_focus.dart';

class _MemoryStorage implements Storage {
  final Map<String, dynamic> _data = {};

  @override
  dynamic read(String key) => _data[key];

  @override
  Future<void> write(String key, dynamic value) async => _data[key] = value;

  @override
  Future<void> delete(String key) async => _data.remove(key);

  @override
  Future<void> clear() async => _data.clear();

  @override
  Future<void> close() async {}
}

/// Where you have to click to type.
///
/// A `TextField` claims the strip its glyphs sit on and nothing else, so a
/// field drawn inside a taller bar has most of its apparent area inert — you
/// had to aim at the placeholder text to get a caret. These tap the corners and
/// the padding of each bar, which is where a person aims and where nothing used
/// to happen.
void main() {
  setUpAll(() => HydratedBloc.storage = _MemoryStorage());

  Future<void> host(WidgetTester tester, Widget child) {
    return tester.pumpWidget(
      BlocProvider<ThemeCubit>(
        create: (_) => ThemeCubit(),
        child: MaterialApp(
          home: Scaffold(
            body: Center(child: SizedBox(width: 460, child: child)),
          ),
        ),
      ),
    );
  }

  bool focused(WidgetTester tester, {int at = 0}) => tester
      .widgetList<EditableText>(find.byType(EditableText))
      .elementAt(at)
      .focusNode
      .hasFocus;

  /// Every corner of [box], inset just enough to be inside it — the places a
  /// finger lands when it is aimed at the bar rather than at the text.
  List<Offset> corners(Rect box, {double inset = 3}) => [
    box.topLeft + Offset(box.width / 2, inset),
    box.bottomLeft + Offset(box.width / 2, -inset),
    box.centerRight - Offset(inset, 0),
  ];

  group('the message composer', () {
    Future<Rect> pumpComposer(
      WidgetTester tester, {
      bool enabled = true,
      void Function(String, List)? onSend,
    }) async {
      await host(
        tester,
        ChatComposer(enabled: enabled, onSend: onSend ?? (_, _) {}),
      );
      // The painted bar, not the outer padding around it.
      return tester.getRect(find.byType(TapToFocus));
    }

    // Run on every platform the app ships on, not just the test default. A
    // text field on desktop unfocuses itself on a tap *outside* its own tap
    // region, so the bar taking the tap and the field dropping it would be the
    // same event — which is why [TapToFocus] declares itself part of the
    // region rather than calling `requestFocus` and hoping.
    testWidgets(
      'takes a click anywhere on the bar, not just on the text',
      (tester) async {
        final bar = await pumpComposer(tester);

        // The dead band is real and large: the line of text is 19px of a 46px
        // bar. If that ever stops being true this test is measuring nothing,
        // so assert the gap rather than assuming it.
        final text = tester.getRect(find.byType(EditableText));
        expect(bar.height - text.height, greaterThan(12));

        for (final point in corners(bar)) {
          await tester.tapAt(point);
          await tester.pump();
          expect(focused(tester), isTrue, reason: 'tapped $point in $bar');
          // Unfocus, so the next corner proves itself rather than coasting on
          // the last one.
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pump();
        }
      },
      variant: TargetPlatformVariant.all(),
    );

    testWidgets('the buttons on the bar are still buttons', (tester) async {
      // The whole point of deferring to the innermost recogniser: a tap that
      // lands on a control belongs to the control, not to the bar under it.
      var sent = 0;
      final bar = await pumpComposer(tester, onSend: (_, _) => sent++);

      await tester.tapAt(bar.centerLeft + const Offset(60, 0));
      await tester.pump();
      await tester.enterText(find.byType(EditableText), 'hi');
      await tester.pump();

      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump();
      expect(sent, 1);
    });

    testWidgets('a composer that cannot be typed in takes no caret', (
      tester,
    ) async {
      final bar = await pumpComposer(tester, enabled: false);
      await tester.tapAt(bar.topLeft + Offset(bar.width / 2, 3));
      await tester.pump();
      expect(focused(tester), isFalse);
    });
  });

  testWidgets('a search pill answers across its whole height', (tester) async {
    await host(
      tester,
      SearchDropdownField<String>(
        hintText: 'Find someone',
        onSearch: (_) async => const [],
        itemBuilder: (_, item, _) => Text(item),
      ),
    );

    final pill = tester.getRect(find.byType(TapToFocus));
    for (final point in corners(pill)) {
      await tester.tapAt(point);
      await tester.pump();
      expect(focused(tester), isTrue, reason: 'tapped $point in $pill');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
    }
    // Including the magnifier, which looks like part of the field and is one.
    await tester.tap(find.byIcon(Icons.search_rounded));
    await tester.pump();
    expect(focused(tester), isTrue);

    // The field debounces the query and waits out a blur before tearing down
    // its overlay; leave neither timer pending on the way out.
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
  });

  testWidgets('a plain field already answers across its own box', (
    tester,
  ) async {
    // The baseline the bars are being brought up to. Material's own field
    // hit-tests its whole decoration, padding included — which is why
    // `AppTextField` needs nothing doing to it, and why this asserts that
    // rather than leaving it as something somebody remembers.
    await host(
      tester,
      AppTextField(controller: TextEditingController(), hint: 'Anything'),
    );

    final box = tester.getRect(find.byType(TextField));
    await tester.tapAt(box.topLeft + const Offset(4, 2));
    await tester.pump();
    expect(focused(tester), isTrue);
  });

  testWidgets('a label answers for the field under it', (tester) async {
    await host(
      tester,
      AppTextField(
        controller: TextEditingController(),
        label: 'Display name',
        hint: 'Anything',
      ),
    );

    await tester.tap(find.text('DISPLAY NAME'));
    await tester.pump();
    expect(focused(tester), isTrue);
  });

  testWidgets('a disabled field is not focused by its label', (tester) async {
    await host(
      tester,
      AppTextField(
        controller: TextEditingController(),
        label: 'Display name',
        enabled: false,
      ),
    );

    await tester.tap(find.text('DISPLAY NAME'));
    await tester.pump();
    expect(focused(tester), isFalse);
  });

  testWidgets('a field driven from outside keeps answering to its owner', (
    tester,
  ) async {
    // The label focuses whichever node the field is actually using, so a
    // caller that supplies one still gets told when the label is clicked —
    // and its own `requestFocus` still lands.
    final node = FocusNode();
    addTearDown(node.dispose);
    await host(
      tester,
      AppTextField(
        controller: TextEditingController(),
        label: 'Handle',
        focusNode: node,
      ),
    );

    await tester.tap(find.text('HANDLE'));
    await tester.pump();
    expect(node.hasFocus, isTrue);
  });
}
