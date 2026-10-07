import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/classes/server.dart';
import 'package:rift/data/constants.dart';
import 'package:rift/logic/cubits/notifications/server_notifications_cubit.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/screens/home/servers/server_rail/widgets/rail_server_chip.dart';
import 'package:rift/presentation/screens/home/servers/server_rail/widgets/rail_unread_badge.dart';

import 'support/rebuild_counter.dart';

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

/// Unread counts the test sets by hand.
class _StubNotificationsCubit extends Cubit<NotificationsState>
    implements ServerNotificationsCubit {
  _StubNotificationsCubit() : super(const NotificationsState());

  void unread(String serverId, int count) => emit(
    NotificationsState(
      unreadByServer: {
        ...state.unreadByServer,
        serverId: {'channel': count},
      },
    ),
  );

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Server _server([String id = 'srv-1']) => Server(
  id: id,
  name: 'Rift HQ',
  supabaseUrl: 'https://hq.example.co',
  token: 't',
);

Future<ThemeState> _pumpChip(
  WidgetTester tester, {
  required bool isSelected,
}) async {
  final themeCubit = ThemeCubit();
  await tester.pumpWidget(
    MaterialApp(
      home: MultiBlocProvider(
        providers: [
          BlocProvider.value(value: themeCubit),
          BlocProvider<ServerNotificationsCubit>(
            create: (_) => _StubNotificationsCubit(),
          ),
        ],
        child: Scaffold(
          body: Center(
            child: RailServerChip(
              server: _server(),
              isSelected: isSelected,
              onTap: () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return themeCubit.state;
}

/// Every box the halo paints, outermost first.
List<BoxDecoration> _haloLayers(WidgetTester tester) {
  return tester
      .widgetList<DecoratedBox>(
        find.descendant(
          of: find.byType(RailServerChip),
          matching: find.byType(DecoratedBox),
        ),
      )
      .map((box) => box.decoration)
      .whereType<BoxDecoration>()
      // The avatar itself paints a gradient, not a flat colour.
      .where((decoration) => decoration.color != null)
      .toList();
}

void main() {
  setUp(() => HydratedBloc.storage = _MemoryStorage());

  group('the selected server chip', () {
    testWidgets('rings the chip instead of backing it', (tester) async {
      final theme = await _pumpChip(tester, isSelected: true);
      final layers = _haloLayers(tester);

      expect(layers, hasLength(2));
      // Accent outside, panel colour inside. Reversed — which is what CSS's
      // paint order does and Flutter's does not — the accent covers the gap
      // and the halo reads as a slab behind the icon.
      expect(layers.first.color, theme.primary.withValues(alpha: 0.8));
      expect(layers.last.color, theme.bgSecondary);
      // Opaque, or the accent shows through the gap and the ring is lost.
      expect(layers.last.color!.a, 1.0);
    });

    testWidgets('steps each corner out with its box', (tester) async {
      await _pumpChip(tester, isSelected: true);
      final layers = _haloLayers(tester);

      double cornerOf(BoxDecoration decoration) =>
          (decoration.borderRadius! as BorderRadius).topLeft.x;

      // A constant radius on a growing box pinches the ring at the corners.
      expect(cornerOf(layers.first), greaterThan(cornerOf(layers.last)));
      expect(cornerOf(layers.last), greaterThan(K.radiusRailChip));
    });

    testWidgets('does not resize the chip', (tester) async {
      await _pumpChip(tester, isSelected: false);
      final unselected = tester.getSize(find.byType(RailServerChip));

      await _pumpChip(tester, isSelected: true);
      final selected = tester.getSize(find.byType(RailServerChip));

      // The halo overhangs. If it counted toward layout, picking a server
      // would nudge every chip below it down the rail.
      expect(selected, unselected);
      expect(selected.width, K.serverRailChipSize);
    });
  });

  testWidgets('an unselected chip paints no halo', (tester) async {
    await _pumpChip(tester, isSelected: false);

    expect(_haloLayers(tester), isEmpty);
  });

  testWidgets('a message on one server redraws that server\'s chip only', (
    tester,
  ) async {
    // The rail used to hand every chip its count from one builder, so a
    // message anywhere redrew every server in it.
    final notifications = _StubNotificationsCubit();
    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<ThemeCubit>(create: (_) => ThemeCubit()),
            BlocProvider<ServerNotificationsCubit>.value(value: notifications),
          ],
          child: Scaffold(
            body: Column(
              children: [
                for (final id in ['srv-1', 'srv-2', 'srv-3'])
                  RailServerChip(
                    server: _server(id),
                    isSelected: false,
                    onTap: () {},
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    final counts = await countRebuilds(() async {
      notifications.unread('srv-2', 4);
      await tester.pump();
    });
    expect(counts[RailServerChip], 1);
    expect(find.byType(RailUnreadBadge), findsOneWidget);
  });
}
