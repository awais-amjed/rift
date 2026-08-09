import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/classes/channel.dart';
import 'package:rift/data/classes/server.dart';
import 'package:rift/data/classes/server_user.dart';
import 'package:rift/data/classes/user_permissions.dart';
import 'package:rift/data/enums/channel_type.dart';
import 'package:rift/logic/cubits/server/server_cubit.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/context_menu_region.dart';
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

/// Members get no channel menu at all, rather than one offering a rename and a
/// delete that `channels_update_managers` and `channels_delete_managers` would
/// refuse. Their right-click has to fall through untouched.
void main() {
  setUpAll(() => HydratedBloc.storage = _MemoryStorage());

  const channel = Channel(
    id: 'c1',
    name: 'general',
    channelType: ChannelType.text,
  );
  const childKey = Key('child');

  Future<void> pump(WidgetTester tester, {required bool canManage}) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider<ThemeCubit>(create: (_) => ThemeCubit()),
              BlocProvider<ServerCubit>(
                create: (_) => _StubServerCubit(canManage),
              ),
            ],
            child: Builder(
              builder: (context) => ChannelContextMenu.wrap(
                context: context,
                channel: channel,
                child: const SizedBox(key: childKey, width: 100, height: 30),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('a channel manager gets the menu', (tester) async {
    await pump(tester, canManage: true);

    expect(find.byType(ContextMenuRegion), findsOneWidget);
    expect(find.byKey(childKey), findsOneWidget);
  });

  testWidgets('a member gets the row back untouched', (tester) async {
    await pump(tester, canManage: false);

    expect(find.byType(ContextMenuRegion), findsNothing);
    expect(find.byKey(childKey), findsOneWidget);
  });
}
