import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/classes/channel.dart';
import 'package:rift/data/classes/participant_info.dart';
import 'package:rift/data/enums/channel_type.dart';
import 'package:rift/logic/cubits/app/app_cubit.dart';
import 'package:rift/logic/cubits/channel_presence/channel_presence_cubit.dart';
import 'package:rift/logic/cubits/server/server_cubit.dart';
import 'package:rift/logic/cubits/server_members/server_members_cubit.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/logic/cubits/voice_listeners/voice_listeners_cubit.dart';
import 'package:rift/logic/services/participant_roster.dart';
import 'package:rift/presentation/common/calls/call_clock.dart';
import 'package:rift/presentation/common/speaking_ring.dart';
import 'package:rift/presentation/screens/home/channels/channel_list/widgets/voice_channel_tile/voice_channel_tile.dart';
import 'package:rift/presentation/screens/home/channels/channel_list/widgets/voice_channel_tile/widgets/channel_roster.dart';
import 'package:rift/presentation/screens/home/sidebar/widgets/participant_list_item.dart';

import 'support/memory_storage.dart';
import 'support/rebuild_counter.dart';
import 'support/stub_members_cubit.dart';

class _StubPresenceCubit extends Cubit<ChannelPresenceState>
    implements ChannelPresenceCubit {
  _StubPresenceCubit() : super(const ChannelPresenceState());

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubServerCubit extends Cubit<ServerState> implements ServerCubit {
  _StubServerCubit() : super(const ServerState());

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubVoiceListenersCubit extends Cubit<VoiceBotsState>
    implements VoiceListenersCubit {
  _StubVoiceListenersCubit() : super(const VoiceBotsState());

  @override
  List<String> listening(String channelId) => const [];

  @override
  List<SummonedBot> summoned(String channelId) => const [];

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ParticipantInfo _person(
  String id, {
  bool speaking = false,
  bool mic = true,
  bool local = false,
}) => ParticipantInfo(
  identity: '$id:device',
  userId: id,
  name: id,
  isSpeaking: speaking,
  isMicrophoneEnabled: mic,
  isLocal: local,
);

/// Counts its own paints, to tell whether a neighbour's animation reaches it.
class _PaintCounter extends CustomPainter {
  int paints = 0;

  @override
  void paint(Canvas canvas, Size size) => paints++;

  @override
  bool shouldRepaint(_PaintCounter old) => false;
}

/// How much of a call a breath redraws.
///
/// Speaking flips several times a second for each person talking, and only
/// the ring round that person shows it. Everything else — every voice channel
/// in the sidebar, the call bar, each tile — used to rebuild with it, and the
/// ring's pulse repainted the whole window sixty times a second.
void main() {
  setUpAll(() => HydratedBloc.storage = MemoryStorage());

  group('ParticipantInfo', () {
    test('equal when every field is', () {
      expect(_person('a'), _person('a'));
      expect(_person('a').hashCode, _person('a').hashCode);
      expect(_person('a'), isNot(_person('a', mic: false)));
    });

    test('speaking is the one difference sameApartFromSpeaking ignores', () {
      expect(
        _person('a').sameApartFromSpeaking(_person('a', speaking: true)),
        isTrue,
      );
      expect(
        _person('a').sameApartFromSpeaking(_person('a', mic: false)),
        isFalse,
      );
      expect(_person('a'), isNot(_person('a', speaking: true)));
    });

    test('a roster changes apart from speaking only with who, or how', () {
      final before = [_person('a'), _person('b')];
      RosterApartFromSpeaking of(List<ParticipantInfo> list) =>
          RosterApartFromSpeaking(list);
      expect(of(before), of([_person('a', speaking: true), _person('b')]));
      expect(of(before), isNot(of([_person('a')])));
      expect(of(before), isNot(of([_person('b'), _person('a')])));
      expect(of(before), isNot(of([_person('a'), _person('b', mic: false)])));
    });
  });

  group('a voice channel in the sidebar', () {
    late AppCubit app;

    Future<void> pump(WidgetTester tester) async {
      app = AppCubit();
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<ThemeCubit>(create: (_) => ThemeCubit()),
            BlocProvider<AppCubit>.value(value: app),
            BlocProvider<ServerCubit>(create: (_) => _StubServerCubit()),
            BlocProvider<ServerMembersCubit>(create: (_) => StubMembersCubit()),
            BlocProvider<VoiceListenersCubit>(
              create: (_) => _StubVoiceListenersCubit(),
            ),
            BlocProvider<ChannelPresenceCubit>(
              create: (_) => _StubPresenceCubit(),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 240,
                child: Column(
                  children: [
                    for (final id in ['mine', 'other'])
                      VoiceChannelTile(
                        channel: Channel(
                          id: id,
                          name: id,
                          channelType: ChannelType.voice,
                        ),
                        isSelected: id == 'mine',
                        onTap: () {},
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      app.setParticipants([_person('a', local: true), _person('b')]);
      await tester.pump();
    }

    testWidgets('redraws only the speaker\'s ring when they talk', (
      tester,
    ) async {
      await pump(tester);
      expect(find.byType(ParticipantListItem), findsNWidgets(2));

      final counts = await countRebuilds(() async {
        app.setParticipants([
          _person('a', local: true),
          _person('b', speaking: true),
        ]);
        await tester.pump();
      });
      expect(counts[VoiceChannelTile], isNull);
      expect(counts[ChannelRoster], isNull);
      expect(counts[ParticipantListItem], isNull);
      expect(counts[SpeakingRing], 1);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('redraws the card when somebody mutes', (tester) async {
      await pump(tester);
      final counts = await countRebuilds(() async {
        app.setParticipants([
          _person('a', local: true),
          _person('b', mic: false),
        ]);
        await tester.pump();
      });
      // Your own channel's card, and not the other channel's.
      expect(counts[ChannelRoster], 1);
    });
  });

  testWidgets('a call\'s clock ticks without its neighbours', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Row(
          children: [
            const Text('neighbour'),
            CallClock(
              since: DateTime.now().subtract(const Duration(minutes: 4)),
              style: const TextStyle(),
            ),
          ],
        ),
      ),
    );
    final counts = await countRebuilds(() async {
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
    });
    expect(counts[CallClock], 3);
    expect(counts[Row], isNull);
    // The clock's own text, and not its neighbour's.
    expect(counts[Text], 3);
  });

  testWidgets('the speaking ring repaints only itself', (tester) async {
    final neighbour = _PaintCounter();
    final inside = _PaintCounter();
    Widget build({required bool speaking}) => MultiBlocProvider(
      providers: [BlocProvider<ThemeCubit>(create: (_) => ThemeCubit())],
      child: MaterialApp(
        home: Row(
          children: [
            CustomPaint(painter: neighbour, size: const Size(40, 40)),
            const SizedBox(width: 20),
            SpeakingRing(
              isSpeaking: speaking,
              borderRadius: BorderRadius.circular(8),
              child: CustomPaint(painter: inside, size: const Size(40, 40)),
            ),
          ],
        ),
      ),
    );
    await tester.pumpWidget(build(speaking: false));
    await tester.pumpWidget(build(speaking: true));
    final neighbourBefore = neighbour.paints;
    final insideBefore = inside.paints;

    // A second of breathing.
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(neighbour.paints, neighbourBefore);
    expect(inside.paints, insideBefore);
  });
}
