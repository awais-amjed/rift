import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/context_menu/context_menu_item.dart';
import 'package:rift/presentation/screens/home/sidebar/widgets/participant_removal_items.dart';

/// Who may disconnect and who may ban.
///
/// Worth pinning because the cost of getting it wrong is asymmetric: offering
/// a button the server refuses is a confusing dead end, but offering one it
/// *accepts* to someone who shouldn't have it is a hole. Both actions are
/// gated in the widget above this one, so these assert the contract this one
/// exposes rather than re-deriving the permissions.
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

Future<void> _pump(
  WidgetTester tester, {
  required bool canDisconnect,
  required bool canBan,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: BlocProvider(
        create: (_) => ThemeCubit(),
        child: Scaffold(
          body: ParticipantRemovalItems(
            targetUserId: 'u1',
            name: 'Foxtrot Desk',
            canDisconnect: canDisconnect,
            canBan: canBan,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUp(() => HydratedBloc.storage = _MemoryStorage());

  testWidgets('offers nothing when the viewer may do neither', (tester) async {
    await _pump(tester, canDisconnect: false, canBan: false);

    expect(find.text('Disconnect'), findsNothing);
    expect(find.text('Ban from server'), findsNothing);
  });

  testWidgets('a moderator who is not an admin gets only Disconnect', (
    tester,
  ) async {
    // Disconnect follows "Move to"; banning is `app.is_admin()` only.
    await _pump(tester, canDisconnect: true, canBan: false);

    expect(find.text('Disconnect'), findsOneWidget);
    expect(find.text('Ban from server'), findsNothing);
  });

  testWidgets('an admin looking at someone out of the call gets only Ban', (
    tester,
  ) async {
    // A ban reaches someone who isn't connected; a disconnect has nothing to
    // end.
    await _pump(tester, canDisconnect: false, canBan: true);

    expect(find.text('Disconnect'), findsNothing);
    expect(find.text('Ban from server'), findsOneWidget);
  });

  testWidgets('both, when the viewer is an admin and they are in a call', (
    tester,
  ) async {
    await _pump(tester, canDisconnect: true, canBan: true);

    expect(find.text('Disconnect'), findsOneWidget);
    expect(find.text('Ban from server'), findsOneWidget);
  });

  testWidgets('there is no unban here', (tester) async {
    // A banned member cannot be a live participant, so this menu only ever
    // looks at someone who isn't banned. Lifting one lives in the Members
    // dialog, which reads the real flag.
    await _pump(tester, canDisconnect: true, canBan: true);

    expect(find.text('Lift ban'), findsNothing);
  });

  testWidgets('both are marked destructive', (tester) async {
    await _pump(tester, canDisconnect: true, canBan: true);

    // The red wash is what separates these from the toggles above them in the
    // same list, where every row otherwise looks identical.
    final items = tester.widgetList<ContextMenuItem>(
      find.byType(ContextMenuItem),
    );
    expect(items.length, 2);
    expect(items.every((i) => i.isDangerous), isTrue);
  });
}
