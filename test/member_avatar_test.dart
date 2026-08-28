import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/classes/server_member.dart';
import 'package:rift/data/classes/user_permissions.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/screens/home/members/widgets/member_row.dart';
import 'package:rift/presentation/theme/identity_gradients.dart';

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

const _member = ServerMember(
  id: 'user-7',
  username: 'maya',
  displayName: 'Maya',
  permissions: UserPermissions(),
);

Future<void> _pumpRow(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: BlocProvider(
        create: (_) => ThemeCubit(),
        child: Scaffold(
          body: MemberRow(
            member: _member,
            isSelf: false,
            isExpanded: false,
            isBusy: false,
            canManagePermissions: false,
            canModerate: false,
            onTap: () {},
            onModerate: ({muted, deafened, banned}) {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUp(() => HydratedBloc.storage = _MemoryStorage());

  testWidgets('a member with no picture gets their identity gradient', (
    tester,
  ) async {
    await _pumpRow(tester);

    final decorations = tester
        .widgetList<Container>(find.byType(Container))
        .map((container) => container.decoration)
        .whereType<BoxDecoration>();

    final gradients = decorations
        .map((decoration) => decoration.gradient)
        .whereType<LinearGradient>();

    // The dialog used to draw its own initial on flat grey, which made the
    // same person look like a different one here and in the members panel.
    expect(gradients, isNotEmpty);
    // Seeded by id, so a rename can't recolour someone mid-conversation. The
    // two seeds are checked apart first, or that half of the assertion would
    // hold for the wrong reason.
    final byName = IdentityGradients.forSeed(_member.displayName);
    final byId = IdentityGradients.forSeed(_member.id);
    expect(byId.start, isNot(byName.start));
    expect(gradients.first.colors, byId.gradient.colors);
  });
}
