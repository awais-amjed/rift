import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/enums/notification_level.dart';
import 'package:rift/logic/cubits/notifications/server_notifications_cubit.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/context_menu/context_menu_item.dart';
import 'package:rift/presentation/common/notifications/notification_level_submenu.dart';

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

/// The levels panel, read against what a scope actually resolves to.
///
/// The panel itself is shared by channels, server DMs, central DMs and the
/// rail chip, so what these are really checking is that the *number* it is
/// handed is the one in force — a menu whose tick sits on a level nothing is
/// at is worse than no menu, because it is believed.
void main() {
  setUpAll(() => HydratedBloc.storage = _MemoryStorage());

  NotificationLevel? picked;

  Future<void> pump(WidgetTester tester, NotificationLevel current) {
    picked = null;
    return tester.pumpWidget(
      BlocProvider<ThemeCubit>(
        create: (_) => ThemeCubit(),
        child: MaterialApp(
          home: Scaffold(
            body: NotificationLevelSubmenu(
              current: current,
              onSelected: (level) => picked = level,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('Notifications'));
    await tester.pumpAndSettle();
  }

  Finder tickOn(String label) => find.descendant(
    of: find.widgetWithText(ContextMenuItem, label),
    matching: find.byIcon(Icons.check_rounded),
  );

  testWidgets('a server nobody has touched reads as @mentions', (tester) async {
    // The thing a fresh server is actually at. Every channel on it rings only
    // for mentions until somebody says otherwise, so a rail menu ticking "All
    // messages" was describing a server that does not exist.
    const fresh = NotificationsState();
    await pump(tester, fresh.serverLevel('s1'));

    // Before it is even opened: the parent row wears the level's icon.
    expect(
      find.byIcon(NotificationLevelSubmenu.iconFor(NotificationLevel.mentions)),
      findsOneWidget,
    );

    await open(tester);
    expect(tickOn('Only @mentions'), findsOneWidget);
    expect(tickOn('All messages'), findsNothing);
    expect(tickOn('Nothing'), findsNothing);
  });

  testWidgets('a server turned up says so, and so do its channels', (
    tester,
  ) async {
    const loud = NotificationsState(
      serverLevels: {'s1': NotificationLevel.all},
    );
    expect(loud.serverLevel('s1'), NotificationLevel.all);
    // The half that makes the setting worth having: a channel with no opinion
    // of its own follows the server up, not just the menu.
    expect(loud.channelLevel('s1', 'c1'), NotificationLevel.all);

    await pump(tester, loud.serverLevel('s1'));
    await open(tester);
    expect(tickOn('All messages'), findsOneWidget);
  });

  testWidgets('every level can be picked, and is reported as picked', (
    tester,
  ) async {
    // One open panel, every row tapped in turn: choosing a level is a report,
    // not a dismissal, and the caller is the one that decides what happens
    // next — which is why the rail menu can close itself and a tile's cannot.
    await pump(tester, NotificationLevel.none);
    await open(tester);

    for (final level in NotificationLevel.channelChoices) {
      await tester.tap(find.text(level.label));
      await tester.pumpAndSettle();
      expect(picked, level, reason: level.label);
    }
  });
}
