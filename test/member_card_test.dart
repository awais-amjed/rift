import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/classes/participant_info.dart';
import 'package:rift/data/classes/role.dart';
import 'package:rift/data/classes/server.dart';
import 'package:rift/data/classes/server_member.dart';
import 'package:rift/data/classes/server_user.dart';
import 'package:rift/data/classes/user_permissions.dart';
import 'package:rift/logic/cubits/app/app_cubit.dart';
import 'package:rift/logic/cubits/dm/dm_cubit.dart';
import 'package:rift/logic/cubits/livekit/livekit_cubit.dart';
import 'package:rift/logic/cubits/server/server_cubit.dart';
import 'package:rift/logic/cubits/server_members/server_members_cubit.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/logic/cubits/voice_listeners/voice_listeners_cubit.dart';
import 'package:rift/presentation/screens/home/channels/channel_list/widgets/voice_channel_tile/widgets/member_card/member_card_anchor.dart';
import 'package:rift/presentation/screens/home/channels/channel_list/widgets/voice_channel_tile/widgets/member_card/member_card_layout.dart';
import 'package:toastification/toastification.dart';

import 'support/memory_storage.dart';
import 'support/stub_members_cubit.dart';

class _StubServerCubit extends Cubit<ServerState> implements ServerCubit {
  _StubServerCubit({bool moderator = false})
    : super(
        moderator
            ? ServerState(
                selectedServerId: 's1',
                servers: [
                  Server(
                    id: 's1',
                    name: 'Server1',
                    supabaseUrl: 'http://localhost',
                    token: 't',
                    user: ServerUser(
                      id: 'me',
                      username: 'me',
                      displayName: 'Me',
                      permissions: UserPermissions(isChannelManager: true),
                    ),
                  ),
                ],
              )
            : const ServerState(),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// No bot hears any channel.
class _StubVoiceListenersCubit extends Cubit<VoiceBotsState>
    implements VoiceListenersCubit {
  _StubVoiceListenersCubit() : super(const VoiceBotsState());

  @override
  bool hears(String channelId, String botId) => false;

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
    ServerMembersState? members,
    AppCubit? app,
    bool moderator = false,
  }) async {
    final watched = <String>[];
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<ThemeCubit>(create: (_) => ThemeCubit()),
          BlocProvider<AppCubit>(create: (_) => app ?? AppCubit()),
          BlocProvider<DmCubit>.value(value: dms),
          BlocProvider<VoiceListenersCubit>(
            create: (_) => _StubVoiceListenersCubit(),
          ),
          BlocProvider<ServerCubit>(
            create: (_) => _StubServerCubit(moderator: moderator),
          ),
          BlocProvider<ServerMembersCubit>(
            create: (_) => StubMembersCubit(members),
          ),
          BlocProvider<LiveKitCubit>(create: (_) => _StubLiveKitCubit(call)),
        ],
        child: ToastificationWrapper(
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  SizedBox(
                    width: 240,
                    child: MemberCardAnchor(
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

  testWidgets('somebody not sharing opens the card, without Watch', (
    tester,
  ) async {
    await pump(tester, sharing: false);
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Mute for you'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Message Alice'), findsOneWidget);
    expect(find.text('Sharing their screen'), findsNothing);
    expect(find.text('Join and watch'), findsNothing);
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

  testWidgets('says who they are: roles, a Bot tag, a time-out', (
    tester,
  ) async {
    await pump(
      tester,
      sharing: false,
      members: ServerMembersState(
        loaded: true,
        known: {
          'alice': ServerMember(
            id: 'alice',
            username: 'alice_bot',
            displayName: 'Alice',
            permissions: const UserPermissions(),
            isBot: true,
            timedOutUntil: DateTime.now().add(const Duration(hours: 1)),
          ),
        },
        memberRoles: const {
          'alice': [Role(id: 'r', name: 'Mods', position: 1, permissions: 0)],
        },
      ),
    );
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();

    expect(find.text('@alice_bot'), findsOneWidget);
    expect(find.text('BOT'), findsOneWidget);
    expect(find.text('MODS'), findsOneWidget);
    expect(find.textContaining('Timed out until'), findsOneWidget);
    // A bot has no soundboard to turn down, and is not called.
    expect(find.byTooltip('Mute their soundboard'), findsNothing);
    expect(find.byTooltip('Call'), findsNothing);
    // Nobody here moderates.
    expect(find.text('MODERATION'), findsNothing);
  });

  testWidgets('says how they are in the call, in words', (tester) async {
    final app = AppCubit()
      ..setParticipants(const [
        ParticipantInfo(
          identity: 'alice~d1',
          userId: 'alice',
          name: 'Alice',
          isDeafened: true,
          isMicrophoneEnabled: false,
        ),
      ]);
    await pump(tester, sharing: false, app: app);
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();

    expect(find.text('Deafened'), findsOneWidget);
    // Deafened already says the microphone is off.
    expect(find.text('Muted'), findsNothing);
  });

  testWidgets('a lone moderation button says what it does', (tester) async {
    // An admin cannot be muted, deafened or disconnected, which leaves Move
    // on its own — with room for its name.
    await pump(
      tester,
      sharing: false,
      moderator: true,
      members: ServerMembersState(
        loaded: true,
        known: {
          'alice': ServerMember(
            id: 'alice',
            username: 'alice',
            displayName: 'Alice',
            permissions: UserPermissions(isServerAdmin: true),
          ),
        },
      ),
    );
    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();

    expect(find.text('MODERATION'), findsOneWidget);
    expect(find.text('Move to'), findsOneWidget);
    expect(find.text('Disconnect'), findsNothing);
    expect(find.byTooltip('Server mute'), findsNothing);
  });

  group('where the card goes', () {
    const window = Size(800, 600);
    const card = Size(248, 340);

    test('beside its row, centred on it', () {
      const layout = MemberCardLayout(
        anchor: Rect.fromLTWH(10, 250, 240, 32),
        below: false,
      );
      expect(
        layout.getPositionForChild(window, card),
        Offset(250 + MemberCardLayout.gap, 266 - card.height / 2),
      );
    });

    test('pushed down from the top and up from the foot', () {
      const top = MemberCardLayout(
        anchor: Rect.fromLTWH(10, 0, 240, 32),
        below: false,
      );
      expect(top.getPositionForChild(window, card).dy, MemberCardLayout.margin);
      const foot = MemberCardLayout(
        anchor: Rect.fromLTWH(10, 568, 240, 32),
        below: false,
      );
      expect(
        foot.getPositionForChild(window, card).dy,
        window.height - card.height - MemberCardLayout.margin,
      );
    });

    test('under its row on a phone, inside the screen', () {
      const layout = MemberCardLayout(
        anchor: Rect.fromLTWH(0, 100, 390, 32),
        below: true,
      );
      final at = layout.getPositionForChild(const Size(390, 844), card);
      expect(at.dx, (390 - card.width) / 2);
      expect(at.dy, 132 + MemberCardLayout.gap / 2);
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
