import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/classes/message_reaction.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/chat/reactions/message_reactions_bar.dart';
import 'package:rift/presentation/common/chat/reactions/reaction_chip.dart';

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

/// Which reaction chips move, and which stay still.
///
/// A reaction landing on a message you are looking at is the only sign you get
/// that it happened, so a chip arriving is worth a pop. Scrolling back through
/// a year of chat is not: every old reaction would set itself off, and the one
/// that means "somebody just reacted" would be indistinguishable from the
/// ninety that mean "this is what the backlog looks like". So the bar primes on
/// first build, and these pin that.
void main() {
  setUpAll(() => HydratedBloc.storage = _MemoryStorage());

  MessageReaction reaction(String emoji, int count) =>
      MessageReaction(emoji: emoji, count: count, mine: false);

  Future<void> pump(WidgetTester tester, List<MessageReaction> reactions) {
    return tester.pumpWidget(
      BlocProvider<ThemeCubit>(
        create: (_) => ThemeCubit(),
        child: MaterialApp(
          home: Scaffold(
            body: MessageReactionsBar(
              // Keyed, so re-pumping updates this bar rather than building a
              // fresh one — which would prime again and hide the bug.
              key: const ValueKey('bar'),
              reactions: reactions,

              onToggle: (_) {},
              onAdd: (_) {},
            ),
          ),
        ),
      ),
    );
  }

  bool isNew(WidgetTester tester, String emoji) =>
      tester.widget<ReactionChip>(find.byKey(ValueKey(emoji))).isNew;

  /// Whether the chip is actually mid-entrance, rather than merely having been
  /// told it was new — which is what matters once the bar has moved on and
  /// stopped saying so.
  bool isEntering(WidgetTester tester, String emoji) => find
      .descendant(
        of: find.byKey(ValueKey(emoji)),
        matching: find.byType(TweenAnimationBuilder<double>),
      )
      .evaluate()
      .isNotEmpty;

  testWidgets('what is already on a message when it appears does not pop', (
    tester,
  ) async {
    await pump(tester, [reaction('👍', 3), reaction('🎉', 1)]);

    expect(isNew(tester, '👍'), isFalse);
    expect(isNew(tester, '🎉'), isFalse);
  });

  testWidgets('a reaction that lands afterwards does', (tester) async {
    await pump(tester, [reaction('👍', 3)]);
    await pump(tester, [reaction('👍', 3), reaction('🎉', 1)]);

    expect(isNew(tester, '🎉'), isTrue, reason: 'it just arrived');
    expect(isNew(tester, '👍'), isFalse, reason: 'it was already there');
  });

  testWidgets('a rebuild mid-pop does not cut the pop short', (tester) async {
    await pump(tester, [reaction('👍', 1)]);
    await pump(tester, [reaction('👍', 1), reaction('🎉', 1)]);
    expect(isEntering(tester, '🎉'), isTrue);

    // A count changing elsewhere, a theme change, the row re-laying out — the
    // bar stops calling this chip new the moment any of them happens, and a
    // chip that re-read the answer would snap to full size halfway through
    // its own arrival.
    await pump(tester, [reaction('👍', 2), reaction('🎉', 1)]);
    expect(isNew(tester, '🎉'), isFalse, reason: 'the bar has moved on');
    expect(isEntering(tester, '🎉'), isTrue, reason: 'the chip has not');
  });

  testWidgets('a chip that was there all along never enters', (tester) async {
    await pump(tester, [reaction('👍', 1)]);
    await pump(tester, [reaction('👍', 2)]);

    expect(isEntering(tester, '👍'), isFalse);
  });

  testWidgets('a reaction that comes back is new again', (tester) async {
    // The last person to have picked it takes it away, and somebody puts it
    // back. That is an arrival by any reading, and the bar has no memory worth
    // keeping of a chip that is no longer on screen.
    await pump(tester, [reaction('👍', 1), reaction('🎉', 1)]);
    await pump(tester, [reaction('👍', 1)]);
    await pump(tester, [reaction('👍', 1), reaction('🎉', 1)]);

    expect(isNew(tester, '🎉'), isTrue);
  });

  testWidgets('a chip keeps its own identity when one before it goes', (
    tester,
  ) async {
    // Keyed by emoji rather than by position: without that, removing the first
    // chip shuffles every later one into a new slot, and the pop meant for the
    // arrival lands on whichever chip moved.
    await pump(tester, [reaction('👍', 1), reaction('🎉', 5)]);
    final before = tester.state(find.byKey(const ValueKey('🎉')));

    await pump(tester, [reaction('🎉', 5)]);
    expect(tester.state(find.byKey(const ValueKey('🎉'))), same(before));
  });
}
