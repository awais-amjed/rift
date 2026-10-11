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

    test('a menu\'s options need only a label, as WIRE.md gives them', () {
      // Each option comes back under the menu's own action id. Asking every
      // option for an id of its own dropped them all, so no menu ever drew.
      final menu = parse([
        {
          'type': 'select',
          'action': 'volume',
          'text': 'Volume 50%',
          'options': [
            {'label': '25%', 'value': '25'},
            {'label': '50%', 'value': '50'},
            {'value': 'no-label'},
          ],
        },
      ])!.blocks.single;
      expect(menu.type, PanelBlockType.select);
      expect(menu.actions.map((o) => (o.label, o.action, o.value)), [
        ('25%', 'volume', '25'),
        ('50%', 'volume', '50'),
      ]);
    });

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

  group('a picture', () {
    const channel = '0b5c7d9e-1f20-4a3b-8c4d-5e6f708192a3';
    const other = '9f8e7d6c-5b4a-4321-8fed-cba987654321';
    final sha = '${'A' * 43}=';

    Map<String, Object?> image(String path, {Object? sha256}) => {
      'type': 'image',
      'path': path,
      'sha256': sha256 ?? sha,
      'width': 300,
      'height': 300,
      'text': 'Album art',
    };

    Panel? parseIn(List<Object?> blocks) =>
        Panel.tryParse({'v': 1, 'blocks': blocks}, channelId: channel);

    test('one stored under the panel\'s own channel is drawn', () {
      final block = parseIn([image('$channel/cover_01.jpg')])!.blocks.single;
      expect(block.type, PanelBlockType.image);
      expect(block.text, 'Album art');
      final attachment = block.image!.attachment;
      // Drawn as a file sent unencrypted: checked against its digest rather
      // than opened with a key it does not have.
      expect(attachment.isEncrypted, isFalse);
      expect(attachment.storagePath, '$channel/cover_01.jpg');
      expect(attachment.mime, 'image/jpeg');
      expect((attachment.width, attachment.height), (300, 300));
    });

    test('never a URL, and never a path out of the channel\'s folder', () {
      // A URL is the whole reason there was no image block: every member's
      // client fetching from wherever a bot pointed.
      for (final path in [
        'https://example.com/cover.jpg',
        '$channel/../$other/cover.jpg',
        '$channel/sub/cover.jpg',
        'dm_${channel}_$other/cover.jpg',
        '$channel/cover.svg',
        '$channel/cover',
      ]) {
        expect(parseIn([image(path)]), isNull, reason: path);
      }
    });

    test('one borrowed from another channel is dropped', () {
      expect(parseIn([image('$other/cover.png')]), isNull);
      // Nor drawn where the channel is not known at all.
      expect(
        Panel.tryParse({
          'v': 1,
          'blocks': [image('$channel/a.png')],
        }),
        isNull,
      );
    });

    test('one without a digest is not drawn', () {
      for (final digest in [null, '', 'abc', '${'A' * 44}=']) {
        final block = image('$channel/a.png', sha256: digest)
          ..update('sha256', (_) => digest);
        expect(parseIn([block]), isNull, reason: '$digest');
      }
    });

    test('a nonsense size is ignored rather than laid out', () {
      final block = parseIn([
        {...image('$channel/a.webp'), 'width': -4, 'height': 1e9},
      ])!.blocks.single;
      expect((block.image!.width, block.image!.height), (null, null));
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
