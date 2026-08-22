import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/enums/layout_mode.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/screens/home/dms/widgets/dm_surface.dart';

import 'shell_scope_harness.dart';

/// In-memory stand-in so [ThemeCubit] (a HydratedCubit) can be built in tests.
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

/// A DM surface is a list-and-detail pair inside a pane that is itself half of
/// one. That nests fine on a desktop and not at all on a phone: 280px of list
/// against a 393px screen left the conversation a gutter, and the resting
/// state was a panel telling you to pick from a list there was no room to
/// show. So the pair collapses to one column at a time on compact.
void main() {
  setUpAll(() => HydratedBloc.storage = _MemoryStorage());

  Future<void> pump(
    WidgetTester tester, {
    required LayoutMode mode,
    required double width,
    Widget? conversation,
  }) async {
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: Size(width, 800)),
        child: MaterialApp(
          home: BlocProvider(
            create: (_) => ThemeCubit(),
            child: withShellScope(
              mode: mode,
              Scaffold(
                // Tight constraints: in the app a DM surface is handed a pane,
                // and a Scaffold body would leave it free to shrink-wrap.
                body: SizedBox.expand(
                  child: DmSurface(
                    emptyTitle: 'Server DMs',
                    emptyMessage: 'Pick a conversation.',
                    conversation: conversation,
                    list: const Text('the list'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a desktop shows the list beside the conversation', (
    tester,
  ) async {
    await pump(
      tester,
      mode: LayoutMode.expanded,
      width: 1400,
      conversation: const Text('the conversation'),
    );

    expect(find.text('the list'), findsOneWidget);
    expect(find.text('the conversation'), findsOneWidget);
    expect(
      tester.getSize(find.text('the list').first).width,
      lessThanOrEqualTo(DmSurface.listWidth),
    );
  });

  testWidgets('a desktop with nothing open still shows the list', (
    tester,
  ) async {
    await pump(tester, mode: LayoutMode.expanded, width: 1400);

    expect(find.text('the list'), findsOneWidget);
    expect(find.text('Server DMs'), findsOneWidget, reason: 'the empty panel');
  });

  testWidgets('a phone gives the whole pane to the list', (tester) async {
    await pump(tester, mode: LayoutMode.compact, width: 393);

    // Not squeezed into a column a third of the screen wide, and no "pick a
    // conversation" panel sitting where the list would go.
    expect(find.text('the list'), findsOneWidget);
    expect(find.text('Server DMs'), findsNothing);
    expect(
      tester.getSize(find.text('the list')).width,
      tester.getSize(find.byType(DmSurface)).width,
    );
  });

  testWidgets('a phone gives the whole pane to the conversation', (
    tester,
  ) async {
    await pump(
      tester,
      mode: LayoutMode.compact,
      width: 393,
      conversation: const Text('the conversation'),
    );

    // The list steps aside rather than sharing: closing the conversation is
    // what brings it back, which is the ordinary phone pattern.
    expect(find.text('the conversation'), findsOneWidget);
    expect(find.text('the list'), findsNothing);
  });
}
