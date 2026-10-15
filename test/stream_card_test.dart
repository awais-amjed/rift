import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:toastification/toastification.dart';
import 'package:rift/logic/cubits/app/app_cubit.dart';
import 'package:rift/logic/cubits/dm/dm_cubit.dart';
import 'package:rift/logic/cubits/livekit/livekit_cubit.dart';
import 'package:rift/logic/cubits/server/server_cubit.dart';
import 'package:rift/logic/cubits/server_members/server_members_cubit.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/screens/home/channels/channel_list/widgets/voice_channel_tile/widgets/stream_card/stream_card_anchor.dart';
import 'package:rift/presentation/screens/home/channels/channel_list/widgets/voice_channel_tile/widgets/stream_card/stream_card_layout.dart';

import 'support/memory_storage.dart';
import 'support/stub_members_cubit.dart';

class _StubServerCubit extends Cubit<ServerState> implements ServerCubit {
  _StubServerCubit() : super(const ServerState());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A DM cubit that records what it was asked to send.
class _StubDmCubit extends Cubit<DmState> implements DmCubit {
  _StubDmCubit() : super(const DmState());

  final sent = <String>[];

  @override
  Future<String?> sendQuickDm({
    required String peerId,
    required String peerName,
    required String text,
  }) async {
    sent.add('$peerId: $text');
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A call cubit holding whatever state the test gives it, and nothing else.
class _StubLiveKitCubit extends Cubit<LiveKitState> implements LiveKitCubit {
  _StubLiveKitCubit(super.initial);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _StubDmCubit dms;
  setUp(() => dms = _StubDmCubit());
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
          BlocProvider<AppCubit>(create: (_) => AppCubit()),
          BlocProvider<DmCubit>.value(value: dms),
          BlocProvider<ServerCubit>(create: (_) => _StubServerCubit()),
          BlocProvider<ServerMembersCubit>(create: (_) => StubMembersCubit()),
          BlocProvider<LiveKitCubit>(create: (_) => _StubLiveKitCubit(call)),
        ],
        child: ToastificationWrapper(
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

  testWidgets('the card carries quick controls for them', (tester) async {
    await pump(tester, sharing: true);
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();

    expect(find.text('VOLUME'), findsOneWidget);
    expect(find.byTooltip('Mute for you'), findsOneWidget);
    expect(find.byTooltip('Hide my voice from them'), findsOneWidget);
    // Moderation needs the permission and a call shared with them.
    expect(find.byTooltip('Server mute'), findsNothing);

    // A press is a toggle that leaves the card open.
    await tester.tap(find.byTooltip('Mute their soundboard'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Unmute their soundboard'), findsOneWidget);
  });

  testWidgets('Enter in the message box sends them a DM', (tester) async {
    await pump(tester, sharing: true);
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();

    final box = find.widgetWithText(TextField, 'Message Alice');
    await tester.enterText(box, 'nice stream');
    // Shift+Enter is a new line, not a send.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    expect(dms.sent, isEmpty);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(dms.sent, ['alice: nice stream']);
    // Let the sent toast run out.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  group('where the card goes', () {
    const window = Size(800, 600);
    const card = Size(248, 340);

    test('beside its row, centred on it', () {
      const layout = StreamCardLayout(
        anchor: Rect.fromLTWH(10, 250, 240, 32),
        below: false,
      );
      expect(
        layout.getPositionForChild(window, card),
        Offset(250 + StreamCardLayout.gap, 266 - card.height / 2),
      );
    });

    test('pushed down from the top and up from the foot', () {
      const top = StreamCardLayout(
        anchor: Rect.fromLTWH(10, 0, 240, 32),
        below: false,
      );
      expect(top.getPositionForChild(window, card).dy, StreamCardLayout.margin);
      const foot = StreamCardLayout(
        anchor: Rect.fromLTWH(10, 568, 240, 32),
        below: false,
      );
      expect(
        foot.getPositionForChild(window, card).dy,
        window.height - card.height - StreamCardLayout.margin,
      );
    });

    test('under its row on a phone, inside the screen', () {
      const layout = StreamCardLayout(
        anchor: Rect.fromLTWH(0, 100, 390, 32),
        below: true,
      );
      final at = layout.getPositionForChild(const Size(390, 844), card);
      expect(at.dx, (390 - card.width) / 2);
      expect(at.dy, 132 + StreamCardLayout.gap / 2);
    });
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
