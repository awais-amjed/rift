import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/classes/channel.dart';
import 'package:rift/data/classes/server_member.dart';
import 'package:rift/data/classes/user_permissions.dart';
import 'package:rift/data/enums/channel_type.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/logic/services/member_selection.dart';
import 'package:rift/presentation/common/status_chip.dart';
import 'package:rift/presentation/screens/home/channels/channel_list/widgets/channel_lock_badge.dart';
import 'package:rift/presentation/screens/home/channels/widgets/channel_member_picker.dart';
import 'package:rift/presentation/theme/app_theme.dart';

import 'support/memory_storage.dart';

ServerMember _member(String id, String name, {bool isBot = false}) =>
    ServerMember(
      id: id,
      username: name.toLowerCase(),
      displayName: name,
      permissions: const UserPermissions(),
      isBot: isBot,
    );

void main() {
  setUpAll(() => HydratedBloc.storage = MemoryStorage());

  group('the channel a client was handed', () {
    test('is public unless the server said otherwise', () {
      // Defaulting the other way would draw a lock on every channel served by
      // a database too old to have the column — which is the failure that
      // looks like a feature.
      final channel = Channel.fromJson({
        'id': 'c1',
        'name': 'general',
        'channel_type': 'text',
      });
      expect(channel.isPrivate, isFalse);
    });

    test('carries privacy through a round trip', () {
      const channel = Channel(
        id: 'c1',
        name: 'war-room',
        channelType: ChannelType.text,
        isPrivate: true,
      );
      expect(Channel.fromJson(channel.toJson()).isPrivate, isTrue);
    });

    test('reads only a literal true as private', () {
      // PostgREST returns a real bool, but a null from a stale row or an
      // absent column must not read as "locked" — and `== true` is the only
      // comparison that treats both the same way as false.
      for (final value in <Object?>[null, 'false', 0]) {
        final channel = Channel.fromJson({
          'id': 'c1',
          'name': 'general',
          'channel_type': 'text',
          'is_private': value,
        });
        expect(channel.isPrivate, isFalse, reason: 'is_private = $value');
      }
    });
  });

  group('picking who is in the room', () {
    late MemberSelection selection;
    late List<String> asked;

    /// [results] answers whatever is typed. The picker's search is the
    /// database's now (migration 039), so what a test can check here is that
    /// the question is asked and the answer drawn — not that a local filter
    /// matched, which is the thing that stopped working past a thousand
    /// members.
    Future<void> pump(
      WidgetTester tester,
      List<ServerMember> Function(String query) results, {
      MemberSelection initial = MemberSelection.empty,
    }) async {
      selection = initial;
      asked = [];
      final themeCubit = ThemeCubit();
      await tester.pumpWidget(
        BlocProvider<ThemeCubit>.value(
          value: themeCubit,
          child: MaterialApp(
            theme: AppTheme.fromPalette(
              themeCubit.state.palette,
              Brightness.dark,
            ),
            home: StatefulBuilder(
              builder: (context, setState) => Scaffold(
                body: ChannelMemberPicker(
                  selection: selection,
                  onSearch: (query) async {
                    asked.add(query);
                    return results(query);
                  },
                  onToggle: (member) =>
                      setState(() => selection = selection.toggled(member)),
                ),
              ),
            ),
          ),
        ),
      );
      // The picker asks on mount; let that land before anything is asserted.
      await tester.pumpAndSettle();
    }

    List<ServerMember> Function(String) fixed(List<ServerMember> members) =>
        (_) => members;

    testWidgets('browses on open, without waiting to be typed into', (
      tester,
    ) async {
      await pump(tester, fixed([_member('1', 'Ada'), _member('2', 'Grace')]));
      expect(asked, ['']);
      expect(find.text('Ada'), findsOneWidget);
      expect(find.text('Grace'), findsOneWidget);
    });

    testWidgets('says so when there is nobody else', (tester) async {
      // A one-person server is the state this dialog is most likely to be
      // opened in, and an empty box with no explanation reads as broken.
      await pump(tester, fixed(const []));
      expect(find.text('Nobody else here yet'), findsOneWidget);
    });

    testWidgets('asks the server for what was typed', (tester) async {
      // Not a local filter. The roster arrives a page at a time, so filtering
      // what is in hand answers "No matches" about somebody who is really
      // there — which is the bug this picker was changed to fix.
      await pump(
        tester,
        (query) => query == 'gra' ? [_member('2', 'Grace')] : const [],
      );

      await tester.enterText(find.byType(TextField), 'gra');
      await tester.pumpAndSettle();
      expect(asked, ['', 'gra']);
      expect(find.text('Grace'), findsOneWidget);
    });

    testWidgets('distinguishes no matches from nobody at all', (tester) async {
      await pump(
        tester,
        (query) => query.isEmpty ? [_member('1', 'Ada')] : const [],
      );

      await tester.enterText(find.byType(TextField), 'zz');
      await tester.pumpAndSettle();
      expect(find.text('No matches'), findsOneWidget);
      expect(find.text('Nobody else here yet'), findsNothing);
    });

    testWidgets('a tap selects, and a second one lets go', (tester) async {
      await pump(tester, fixed([_member('1', 'Ada')]));
      expect(find.byIcon(Icons.check_circle_rounded), findsNothing);

      await tester.tap(find.text('Ada'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      expect(selection.ids, {'1'});

      await tester.tap(find.text('Ada'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
      expect(selection.ids, isEmpty);
    });

    testWidgets('shows what was already picked', (tester) async {
      // The same widget has to serve "who is in this channel" later, where it
      // opens with a selection rather than building one.
      await pump(
        tester,
        fixed([_member('1', 'Ada'), _member('2', 'Grace')]),
        initial: MemberSelection.of([_member('2', 'Grace')]),
      );
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);
    });

    testWidgets('somebody already in the channel is drawn even when no page '
        'has reached them', (tester) async {
      // The case the pinned rows exist for. A search that does not return them
      // must not make them vanish from a list they are already in — losing
      // them there means dropping them when the dialog saves.
      await pump(
        tester,
        fixed(const []),
        initial: MemberSelection.of([_member('9', 'Zoe')]),
      );

      expect(find.text('Zoe'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    });
  });

  test('the private chip answers the question nobody asks out loud', () {
    // "Only members can see it" is what the word already means. The sentence
    // that earns its place is the one about the exception people assume exists
    // — and it is the first thing a later edit would trim for length.
    expect(StatusChip.privateTooltip.toLowerCase(), contains('admin'));
    expect(
      StatusChip.privateTooltip.toLowerCase(),
      contains('not an exception'),
    );
  });

  testWidgets('the lock is a lock', (tester) async {
    // Thin, but it is the one thing a member reads to know a room is not the
    // whole server, and it is drawn from one widget in two places.
    final themeCubit = ThemeCubit();
    await tester.pumpWidget(
      BlocProvider<ThemeCubit>.value(
        value: themeCubit,
        child: MaterialApp(home: Scaffold(body: ChannelLockBadge())),
      ),
    );
    expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
  });
}
