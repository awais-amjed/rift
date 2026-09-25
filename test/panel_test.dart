import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/classes/panel_block.dart';
import 'package:rift/data/constants.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/chat/panel/panel_view.dart';
import 'package:rift/presentation/theme/app_theme.dart';

import 'support/memory_storage.dart';

/// A panel is the one thing in Rift drawn from something a *bot* wrote, so the
/// tests that matter are the ones about what it cannot make happen.
void main() {
  setUpAll(() => HydratedBloc.storage = MemoryStorage());

  Panel? parse(List<Object?> blocks) =>
      Panel.tryParse({'v': 1, 'blocks': blocks});

  group('what a bot can and cannot draw', () {
    test('an unknown block type is dropped, not drawn', () {
      // The safety property, and the reason the vocabulary is fixed. A bot
      // built against a newer Rift loses the block this client does not have
      // and keeps the rest, rather than the panel failing whole.
      final panel = parse([
        {'type': 'heading', 'text': 'Now playing'},
        {'type': 'iframe', 'url': 'https://example.com'},
        {'type': 'text', 'text': 'Aphex Twin'},
      ]);
      expect(panel!.blocks.length, 2);
      expect(panel.blocks.map((b) => b.type), [
        PanelBlockType.heading,
        PanelBlockType.text,
      ]);
    });

    test('a block with nothing in it is dropped', () {
      // An empty text block leaves a gap that reads as a bug, and a bot with a
      // formatting error should cost itself a line rather than the panel.
      expect(
        parse([
          {'type': 'text', 'text': ''},
        ]),
        isNull,
      );
      expect(
        parse([
          {'type': 'actions', 'items': []},
        ]),
        isNull,
      );
    });

    test('a malformed panel costs its own message, not the channel', () {
      for (final raw in <Object?>[null, 'blocks', 42, <String, Object?>{}]) {
        expect(Panel.tryParse(raw), isNull, reason: '$raw');
      }
      expect(Panel.tryParse({'blocks': 'nope'}), isNull);
    });

    test('a button needs a label and an action id, or it is not one', () {
      final panel = parse([
        {
          'type': 'actions',
          'items': [
            {'label': 'Skip', 'action': 'skip'},
            {'label': 'Broken'},
            {'action': 'no-label'},
            {'label': 'Long', 'action': 'x' * 65},
          ],
        },
      ]);
      expect(panel!.blocks.single.actions.length, 1);
      expect(panel.blocks.single.actions.single.action, 'skip');
    });

    test(
      'progress is clamped, so a bar cannot be laid out seven times wide',
      () {
        final panel = parse([
          {'type': 'progress', 'value': 7},
          {'type': 'progress', 'value': -3},
        ]);
        expect(panel!.blocks.map((b) => b.value), [1.0, 0.0]);
      },
    );

    test('a style is a weight, never a colour', () {
      // A bot picks how prominent an action is and nothing else. Anything it
      // does not recognise falls back to normal rather than being honoured,
      // so a panel cannot paint itself into looking like Rift's own chrome.
      final panel = parse([
        {
          'type': 'actions',
          'items': [
            {'label': 'A', 'action': 'a', 'style': 'primary'},
            {'label': 'B', 'action': 'b', 'style': '#ff0000'},
          ],
        },
      ]);
      expect(panel!.blocks.single.actions.map((a) => a.style), [
        PanelButtonStyle.primary,
        PanelButtonStyle.normal,
      ]);
    });
  });

  group('pressing one', () {
    Future<void> pump(
      WidgetTester tester,
      Panel panel, {
      void Function(String, String?)? onAction,
    }) {
      final themeCubit = ThemeCubit();
      return tester.pumpWidget(
        BlocProvider<ThemeCubit>.value(
          value: themeCubit,
          child: MaterialApp(
            theme: AppTheme.fromPalette(
              themeCubit.state.palette,
              Brightness.dark,
            ),
            home: Scaffold(
              body: PanelView(panel: panel, onAction: onAction),
            ),
          ),
        ),
      );
    }

    testWidgets('sends the button its own action id', (tester) async {
      String? got;
      await pump(
        tester,
        parse([
          {
            'type': 'actions',
            'items': [
              {'label': 'Skip', 'action': 'skip'},
            ],
          },
        ])!,
        onAction: (action, _) => got = action,
      );
      await tester.tap(find.text('Skip'));
      expect(got, 'skip');
    });

    // A poll's Yes and No once each took the whole card's width: the button
    // was given a height by a Container with an alignment, which grows to
    // every pixel a Wrap offers it.
    testWidgets('a button is its label\'s width and the compact height', (
      tester,
    ) async {
      await pump(
        tester,
        parse([
          {
            'type': 'actions',
            'items': [
              {'label': 'Yes', 'action': 'yes'},
              {'label': 'No', 'action': 'no'},
            ],
          },
        ])!,
        onAction: (_, _) {},
      );
      final button = tester.getSize(
        find.ancestor(of: find.text('Yes'), matching: find.byType(InkWell)),
      );
      expect(button.height, K.compactControlHeight);
      expect(button.width, lessThan(80));
    });

    testWidgets('draws a panel nobody can press, rather than hiding it', (
      tester,
    ) async {
      // A panel is worth reading where it cannot be touched — a locked
      // channel, a member without send rights. Hiding the buttons would leave
      // a poll with no visible options.
      await pump(
        tester,
        parse([
          {
            'type': 'actions',
            'items': [
              {'label': 'Skip', 'action': 'skip'},
            ],
          },
        ])!,
      );
      expect(find.text('Skip'), findsOneWidget);
    });
  });
}
