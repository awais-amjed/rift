import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/logic/cubits/livekit/livekit_cubit.dart';
import 'package:rift/logic/cubits/server_members/server_members_cubit.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/screens/home/channels/channel_list/widgets/voice_channel_tile/widgets/stream_card/stream_card_anchor.dart';

import 'support/memory_storage.dart';
import 'support/stub_members_cubit.dart';

/// A call cubit holding whatever state the test gives it, and nothing else.
class _StubLiveKitCubit extends Cubit<LiveKitState> implements LiveKitCubit {
  _StubLiveKitCubit(super.initial);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() => HydratedBloc.storage = MemoryStorage());

  Future<List<String>> pump(
    WidgetTester tester, {
    required bool sharing,
    LiveKitState call = const LiveKitState(),
  }) async {
    final watched = <String>[];
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<ThemeCubit>(create: (_) => ThemeCubit()),
          BlocProvider<ServerMembersCubit>(create: (_) => StubMembersCubit()),
          BlocProvider<LiveKitCubit>(create: (_) => _StubLiveKitCubit(call)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SizedBox(
                  width: 240,
                  child: StreamCardAnchor(
                    sharing: sharing,
                    userId: 'alice',
                    name: 'Alice',
                    channelId: 'vc-1',
                    onWatch: () => watched.add('alice'),
                    child: const SizedBox(height: 32, child: Text('Alice')),
                  ),
                ),
                const SizedBox(height: 400, child: Text('elsewhere')),
              ],
            ),
          ),
        ),
      ),
    );
    return watched;
  }

  testWidgets('a click on somebody sharing opens the card, and its button '
      'watches', (tester) async {
    final watched = await pump(tester, sharing: true);
    expect(find.text('Join and watch'), findsNothing);

    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();
    expect(find.text('Sharing their screen'), findsOneWidget);
    expect(find.text('Join and watch'), findsOneWidget);

    await tester.tap(find.text('Join and watch'));
    await tester.pumpAndSettle();
    expect(watched, ['alice']);
    expect(find.text('Join and watch'), findsNothing);
  });

  testWidgets('a click anywhere else closes it', (tester) async {
    await pump(tester, sharing: true);
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();
    expect(find.text('Sharing their screen'), findsOneWidget);

    await tester.tap(find.text('elsewhere'));
    await tester.pumpAndSettle();
    expect(find.text('Sharing their screen'), findsNothing);
  });

  testWidgets('a click on the row again closes it', (tester) async {
    await pump(tester, sharing: true);
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alice').first);
    await tester.pumpAndSettle();
    expect(find.text('Sharing their screen'), findsNothing);
  });

  testWidgets('somebody not sharing opens nothing', (tester) async {
    await pump(tester, sharing: false);
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();
    expect(find.text('Sharing their screen'), findsNothing);
  });

  testWidgets('from inside their call the button only watches', (tester) async {
    await pump(
      tester,
      sharing: true,
      call: const LiveKitState(
        connectionState: LiveKitConnectionState.connected,
        currentChannelId: 'vc-1',
      ),
    );
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();
    expect(find.text('Watch stream'), findsOneWidget);
  });

  test('a stream asked for is forgotten with the call', () {
    const connected = LiveKitState(
      connectionState: LiveKitConnectionState.connected,
    );
    final asked = connected.copyWith(streamToOpen: 'alice~d_screenshare');
    expect(asked.streamToOpen, 'alice~d_screenshare');
    expect(
      asked
          .copyWith(connectionState: LiveKitConnectionState.disconnected)
          .streamToOpen,
      isNull,
    );
    expect(asked.copyWith(clearStreamToOpen: true).streamToOpen, isNull);
  });
}
