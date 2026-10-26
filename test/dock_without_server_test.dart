import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/logic/cubits/app/app_cubit.dart';
import 'package:rift/logic/cubits/livekit/livekit_cubit.dart';
import 'package:rift/logic/cubits/server/server_cubit.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/screens/home/profile/edit/profile_edit_modal.dart';
import 'package:rift/presentation/screens/home/profile/user_dock/user_dock.dart';
import 'package:rift/presentation/screens/home/profile/user_dock/widgets/dock_avatar_button.dart';

import 'shell_scope_harness.dart';

/// With no server the dock reads "Guest", and its avatar still opened the
/// profile editor, whose Save had no server to save to and threw (seen on a
/// Play review phone that had just wiped its identity, Oct 24 2026). A
/// profile is a server's, so with none the avatar opens nothing.

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
  _StubServerCubit() : super(const ServerState());

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubLiveKitCubit extends Cubit<LiveKitState> implements LiveKitCubit {
  _StubLiveKitCubit() : super(const LiveKitState());

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() => HydratedBloc.storage = _MemoryStorage());

  testWidgets('with no server, the dock avatar opens no profile editor', (
    tester,
  ) async {
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider(create: (_) => ThemeCubit()),
          BlocProvider(create: (_) => AppCubit()),
          BlocProvider<ServerCubit>(create: (_) => _StubServerCubit()),
          BlocProvider<LiveKitCubit>(create: (_) => _StubLiveKitCubit()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 288,
              child: withShellScope(
                const Column(children: [Spacer(), UserDock()]),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Guest'), findsOneWidget);

    await tester.tap(find.byType(DockAvatarButton));
    await tester.pumpAndSettle();

    expect(find.byType(ProfileEditModal), findsNothing);
    expect(find.byTooltip('Edit profile'), findsNothing);
  });
}
