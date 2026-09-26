import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/classes/channel.dart';
import 'package:rift/data/classes/server.dart';
import 'package:rift/data/classes/server_user.dart';
import 'package:rift/data/classes/user_permissions.dart';
import 'package:rift/data/enums/channel_type.dart';
import 'package:rift/data/enums/notification_level.dart';
import 'package:rift/logic/cubits/notifications/server_notifications_cubit.dart';
import 'package:rift/logic/cubits/server/server_cubit.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/context_menu_region.dart';
import 'package:rift/presentation/common/notifications/notification_level_submenu.dart';
import 'package:rift/presentation/screens/home/channels/channel_list/widgets/channel_context_menu.dart';

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

class _StubServerCubit extends Cubit<ServerState> implements ServerCubit {
  _StubServerCubit(bool isChannelManager)
    : super(
        ServerState(
          selectedServerId: 's1',
          servers: [
            Server(
              id: 's1',
              name: 'Server1',
              supabaseUrl: 'http://localhost',
              token: 't',
              user: ServerUser(
                id: 'u1',
                username: 'me',
                displayName: 'Me',
                permissions: UserPermissions(
                  isChannelManager: isChannelManager,
                ),
              ),
            ),
          ],
        ),
      );

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubNotificationsCubit extends Cubit<NotificationsState>
    implements ServerNotificationsCubit {
  _StubNotificationsCubit() : super(const NotificationsState());

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Everyone gets the channel menu, because everyone has something of their own
/// in it: how much this channel is allowed to interrupt them. What is still
/// conditional is the manager half — a rename and a delete that
/// `channels_update_managers` and `channels_delete_managers` would refuse are
/// not offered to somebody who cannot use them.
void main() {
  setUpAll(() => HydratedBloc.storage = _MemoryStorage());

  const childKey = Key('child');

  Future<void> pump(
    WidgetTester tester, {
    required bool canManage,
    ChannelType type = ChannelType.text,
  }) {
    final channel = Channel(id: 'c1', name: 'general', channelType: type);
    // Providers above the MaterialApp, as `AppProviders` puts them. The menu
    // is an OverlayEntry inside the app's Navigator, so anything provided
    // *inside* the Scaffold is not an ancestor of the panel and the menu
    // builds against nothing.
    return tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<ThemeCubit>(create: (_) => ThemeCubit()),
          BlocProvider<ServerCubit>(create: (_) => _StubServerCubit(canManage)),
          BlocProvider<ServerNotificationsCubit>(
            create: (_) => _StubNotificationsCubit(),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ChannelContextMenu.wrap(
                context: context,
                channel: channel,
                // Painted, not an empty box: a childless SizedBox answers no hit
                // test, so the right-click would sail straight past the region.
                child: Container(
                  key: childKey,
                  width: 100,
                  height: 30,
                  color: Colors.red,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tapAt(
      tester.getCenter(find.byKey(childKey)),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a channel manager gets the whole menu', (tester) async {
    await pump(tester, canManage: true);
    expect(find.byType(ContextMenuRegion), findsOneWidget);

    await open(tester);
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Channel settings'), findsOneWidget);
    expect(find.text('Delete channel'), findsOneWidget);
  });

  testWidgets('a member gets the half that is theirs to set', (tester) async {
    await pump(tester, canManage: false);
    expect(find.byType(ContextMenuRegion), findsOneWidget);

    await open(tester);
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Channel settings'), findsNothing);
    expect(find.text('Delete channel'), findsNothing);
  });

  testWidgets('the row itself is still handed back untouched', (tester) async {
    await pump(tester, canManage: false);
    expect(find.byKey(childKey), findsOneWidget);
  });

  testWidgets('a voice channel has nothing to be notified about', (
    tester,
  ) async {
    await pump(tester, canManage: true, type: ChannelType.voice);
    await open(tester);

    expect(find.text('Notifications'), findsNothing);
    expect(find.text('Delete channel'), findsOneWidget);
  });

  testWidgets('the current level is the one ticked', (tester) async {
    await pump(tester, canManage: false);
    await open(tester);

    // The row's icon says what is in force without opening the submenu — a
    // muted channel should be visible from the menu that mutes it.
    expect(
      find.byIcon(NotificationLevelSubmenu.iconFor(NotificationLevel.mentions)),
      findsOneWidget,
    );
  });
}
