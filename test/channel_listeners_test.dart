import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/screens/home/chat/widgets/channel_listeners_chip.dart';
import 'package:rift/presentation/theme/app_theme.dart';

import 'support/memory_storage.dart';

/// The one bot grant that spends the trust model has to announce itself.
///
/// A moderation bot reads every message in a channel. The admin grants it;
/// every member's future messages pay for it. So the notice cannot live in the
/// admin's dialog, and it cannot be behind a menu — a notice you have to go
/// looking for only tells the people who already knew.
void main() {
  setUpAll(() => HydratedBloc.storage = MemoryStorage());

  Future<void> pump(WidgetTester tester, List<String> listeners) {
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
            body: Center(child: ChannelListenersChip(listeners: listeners)),
          ),
        ),
      ),
    );
  }

  testWidgets('nothing is shown when nothing is listening', (tester) async {
    // The common case by a wide margin, and it must cost the header nothing.
    await pump(tester, const []);
    expect(find.byType(Tooltip), findsNothing);
    expect(find.textContaining('reading'), findsNothing);
  });

  testWidgets('one bot is named on the chip', (tester) async {
    await pump(tester, const ['ModBot']);
    expect(find.text('ModBot is reading'), findsOneWidget);
  });

  testWidgets('several are counted, and named in the tooltip', (tester) async {
    // The label has to fit a header; the names still have to be reachable,
    // because *which* bot is the half somebody can act on.
    await pump(tester, const ['ModBot', 'Watcher']);
    expect(find.text('2 bots reading'), findsOneWidget);

    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tooltip.message, contains('ModBot'));
    expect(tooltip.message, contains('Watcher'));
  });

  testWidgets('it says what the bot can actually do', (tester) async {
    // Not "a bot is present" — that reads as harmless. It holds the key and
    // reads everything from now on, and it says both.
    await pump(tester, const ['ModBot']);
    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tooltip.message, contains('encryption key'));
    expect(tooltip.message, contains('every message'));
  });

  testWidgets('and that a person decided it', (tester) async {
    // The grant is answerable to somebody. A notice that framed it as a
    // property of the channel would hide who to ask about it.
    await pump(tester, const ['ModBot']);
    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tooltip.message!.toLowerCase(), contains('admin granted'));
  });

  testWidgets('it is not hidden behind a hover', (tester) async {
    // The tooltip carries the detail; the *chip* has to carry the fact, with
    // no interaction at all. A marker only visible on hover is invisible on a
    // phone and easy to miss anywhere else.
    await pump(tester, const ['ModBot']);
    expect(find.textContaining('reading'), findsOneWidget);
  });
}
