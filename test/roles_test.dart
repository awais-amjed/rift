import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/classes/role.dart';
import 'package:rift/data/enums/server_permission.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/logic/services/role_ladder.dart';
import 'package:rift/presentation/common/app_switch.dart';
import 'package:rift/presentation/screens/home/roles/widgets/permission_matrix.dart';
import 'package:rift/presentation/theme/app_theme.dart';

import 'support/memory_storage.dart';

void main() {
  setUpAll(() => HydratedBloc.storage = MemoryStorage());

  group('the permission list is a wire contract', () {
    test('every bit is used once', () {
      // The numbers are assigned once in `app.perm_bit` and never reused: a
      // retired permission leaves its bit vacant rather than letting the next
      // one inherit it. Two permissions sharing a bit would mean granting one
      // silently granted the other.
      final bits = ServerPermission.values.map((p) => p.bit).toList();
      expect(bits.toSet().length, bits.length);
    });

    test('the bits are contiguous from zero, so far', () {
      // Not a rule — a retirement would leave a hole and that is allowed. It
      // is a check that nothing has been *skipped* by accident, which is the
      // way a client and a migration drift apart without anyone noticing.
      final bits = ServerPermission.values.map((p) => p.bit).toList()..sort();
      expect(bits, List.generate(bits.length, (i) => i));
    });

    test('every permission says what it lets somebody do', () {
      // A name alone does not: "Manage channels" does not tell you whether it
      // reaches inside a private one, and that answer is the whole reason
      // somebody would tick it.
      for (final permission in ServerPermission.values) {
        expect(
          permission.description.length,
          greaterThan(20),
          reason: '${permission.name} has no description worth reading',
        );
      }
    });

    test('grouping loses nothing', () {
      final grouped = [
        for (final group in PermissionGroup.values)
          ...ServerPermission.inGroup(group),
      ];
      expect(grouped.toSet(), ServerPermission.values.toSet());
    });
  });

  group('what a set of bits means', () {
    test('administrator implies everything, and carries nothing extra', () {
      final bits = ServerPermission.administrator.mask;
      // `has` is the question a button asks: may this person do it?
      expect(bits.has(ServerPermission.banMembers), isTrue);
      // `carries` is the question a checkbox asks: does the role say so?
      // Conflating the two would leave every box ticked in the editor and
      // none of them real — turning administrator off would grant nothing.
      expect(bits.carries(ServerPermission.banMembers), isFalse);
      expect(bits.carries(ServerPermission.administrator), isTrue);
    });

    test('an ordinary bit implies only itself', () {
      final bits = ServerPermission.kickMembers.mask;
      expect(bits.has(ServerPermission.kickMembers), isTrue);
      expect(bits.has(ServerPermission.banMembers), isFalse);
    });

    test('adding and removing are exact', () {
      var bits = 0;
      bits = bits.with_(ServerPermission.speak);
      bits = bits.with_(ServerPermission.connect);
      expect(bits.carries(ServerPermission.speak), isTrue);
      bits = bits.without(ServerPermission.speak);
      expect(bits.carries(ServerPermission.speak), isFalse);
      expect(bits.carries(ServerPermission.connect), isTrue);
    });
  });

  group('a role as the client reads it', () {
    test('a missing colour leaves the name alone', () {
      const role = Role(id: 'r', name: 'Mods', position: 1, permissions: 0);
      expect(role.displayColor, isNull);
    });

    test('a malformed colour is ignored rather than guessed at', () {
      // A server is free to hold anything in that column, and a client that
      // threw would take the whole roles list down with one bad row.
      for (final hex in ['', 'red', '#12', '#GGGGGG']) {
        final role = Role(
          id: 'r',
          name: 'Mods',
          position: 1,
          permissions: 0,
          color: hex,
        );
        expect(role.displayColor, isNull, reason: hex);
      }
    });

    test('a real one comes back opaque', () {
      const role = Role(
        id: 'r',
        name: 'Mods',
        position: 1,
        permissions: 0,
        color: '#22C55E',
      );
      expect(role.displayColor, const Color(0xFF22C55E));
    });
  });

  group('the ladder', () {
    const everyone = Role(
      id: 'e',
      name: '@everyone',
      position: 0,
      permissions: 0,
      isEveryone: true,
    );
    const members = Role(
      id: 'm',
      name: 'Members',
      position: 100,
      permissions: 0,
    );
    const mod = Role(id: 'o', name: 'Moderator', position: 200, permissions: 0);
    const admin = Role(id: 'a', name: 'Admin', position: 300, permissions: 0);
    const owner = Role(
      id: 'w',
      name: 'Owner',
      position: 400,
      permissions: 0,
      isOwner: true,
    );
    const all = [owner, admin, mod, members, everyone];

    test('rank is the highest role actually held', () {
      expect(
        RoleLadder.rankOf({
          'u': const [mod, members],
        }, 'u'),
        200,
      );
    });

    test('holding nothing ranks zero, and reaches nothing', () {
      // `@everyone` does not count: it is never assigned. Zero is right —
      // nothing sits strictly below the ground.
      expect(RoleLadder.rankOf(const {}, 'u'), 0);
      expect(RoleLadder.below(all, 0), isEmpty);
    });

    test('a null user ranks zero rather than throwing', () {
      expect(RoleLadder.rankOf(const {}, null), 0);
    });

    test('editing is strictly below, for everybody', () {
      // Including an administrator: nobody rewrites the role they are standing
      // on, or promotes another up to it.
      expect(RoleLadder.below(all, 300), [mod, members]);
      expect(RoleLadder.below(all, 200), [members]);
    });

    test('the baseline is never on the ladder', () {
      expect(RoleLadder.below(all, 300), isNot(contains(everyone)));
      expect(
        RoleLadder.assignable(all, 300, isAdministrator: true),
        isNot(contains(everyone)),
      );
    });

    test('assigning is the same, unless you are an administrator', () {
      // The exemption exists so the only admin on a server can make a second
      // one. Without it that is impossible, and it stayed possible from 003
      // through to 025 — so a screen that used the editing rule here would
      // quietly take it away.
      expect(RoleLadder.assignable(all, 300, isAdministrator: false), [
        mod,
        members,
      ]);
      expect(RoleLadder.assignable(all, 300, isAdministrator: true), [
        admin,
        mod,
        members,
      ]);
    });

    test('the owner role is nobody\'s to hand out, not even the owner\'s', () {
      // Rank alone keeps it off an admin's list. The administrator exemption
      // would let it through, and the database refuses it — so the ladder
      // says so first.
      expect(
        RoleLadder.assignable(all, 400, isAdministrator: true),
        isNot(contains(owner)),
      );
      expect(RoleLadder.below(all, 400), [admin, mod, members]);
    });
  });

  group('the permission matrix', () {
    Future<void> pump(
      WidgetTester tester, {
      required int permissions,
      required int viewer,
      bool editable = true,
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
              body: SingleChildScrollView(
                child: PermissionMatrix(
                  permissions: permissions,
                  viewerPermissions: viewer,
                  onChanged: editable ? (_, _) {} : null,
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('shows every permission, grouped', (tester) async {
      await pump(
        tester,
        permissions: 0,
        viewer: ServerPermission.administrator.mask,
      );
      for (final group in PermissionGroup.values) {
        expect(find.text(group.label.toUpperCase()), findsOneWidget);
      }
      expect(find.text('Ban members'), findsOneWidget);
      expect(find.text('Share screen'), findsOneWidget);
    });

    testWidgets('a permission the viewer lacks is shown, not hidden', (
      tester,
    ) async {
      // Hiding it would suggest it does not exist. The subset rule is easier
      // to obey once you can see what it is stopping you doing.
      await pump(
        tester,
        permissions: 0,
        viewer: ServerPermission.kickMembers.mask,
      );
      expect(find.text('Ban members'), findsOneWidget);

      final switches = tester
          .widgetList<AppSwitch>(find.byType(AppSwitch))
          .where((s) => s.onChanged != null);
      // Only the one they hold is live. Everything else is visible and inert.
      expect(switches.length, 1);
    });
  });
}
