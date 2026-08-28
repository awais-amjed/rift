import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/classes/channel.dart';
import 'package:rift/data/classes/server_member.dart';
import 'package:rift/data/classes/user_permissions.dart';
import 'package:rift/data/enums/channel_type.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
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
    late Set<String> selected;
    late String query;

    Future<void> pump(
      WidgetTester tester,
      List<ServerMember> members, {
      Set<String>? initial,
    }) {
      selected = initial ?? <String>{};
      query = '';
      final themeCubit = ThemeCubit();
      return tester.pumpWidget(
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
                  themeState: themeCubit.state,
                  members: members,
                  selected: selected,
                  query: query,
                  queryController: TextEditingController(text: query),
                  onQueryChanged: (q) => setState(() => query = q),
                  onToggle: (id) => setState(() {
                    selected.contains(id)
                        ? selected.remove(id)
                        : selected.add(id);
                  }),
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('lists the people it was given', (tester) async {
      await pump(tester, [_member('1', 'Ada'), _member('2', 'Grace')]);
      expect(find.text('Ada'), findsOneWidget);
      expect(find.text('Grace'), findsOneWidget);
    });

    testWidgets('says so when there is nobody else', (tester) async {
      // A one-person server is the state this dialog is most likely to be
      // opened in, and an empty box with no explanation reads as broken.
      await pump(tester, const []);
      expect(find.text('Nobody else here yet'), findsOneWidget);
    });

    testWidgets('filters by display name and by handle', (tester) async {
      await pump(tester, [_member('1', 'Ada'), _member('2', 'Grace')]);

      await tester.enterText(find.byType(TextField), 'gra');
      await tester.pump();
      expect(find.text('Ada'), findsNothing);
      expect(find.text('Grace'), findsOneWidget);

      // The handle is what people type when two members share a display name,
      // so searching only the display name would fail exactly then.
      await tester.enterText(find.byType(TextField), 'ada');
      await tester.pump();
      expect(find.text('Ada'), findsOneWidget);
      expect(find.text('Grace'), findsNothing);
    });

    testWidgets('distinguishes no matches from nobody at all', (tester) async {
      await pump(tester, [_member('1', 'Ada')]);
      await tester.enterText(find.byType(TextField), 'zz');
      await tester.pump();
      expect(find.text('No matches'), findsOneWidget);
      expect(find.text('Nobody else here yet'), findsNothing);
    });

    testWidgets('a tap selects, and a second one lets go', (tester) async {
      await pump(tester, [_member('1', 'Ada')]);
      expect(find.byIcon(Icons.check_circle_rounded), findsNothing);

      await tester.tap(find.text('Ada'));
      await tester.pump();
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      expect(selected, {'1'});

      await tester.tap(find.text('Ada'));
      await tester.pump();
      expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
      expect(selected, isEmpty);
    });

    testWidgets('shows what was already picked', (tester) async {
      // The same widget has to serve "who is in this channel" later, where it
      // opens with a selection rather than building one.
      await pump(
        tester,
        [_member('1', 'Ada'), _member('2', 'Grace')],
        initial: {'2'},
      );
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);
    });
  });

  testWidgets('the lock is a lock', (tester) async {
    // Thin, but it is the one thing a member reads to know a room is not the
    // whole server, and it is drawn from one widget in two places.
    final themeCubit = ThemeCubit();
    await tester.pumpWidget(
      BlocProvider<ThemeCubit>.value(
        value: themeCubit,
        child: MaterialApp(
          home: Scaffold(
            body: ChannelLockBadge(themeState: themeCubit.state),
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
  });
}
