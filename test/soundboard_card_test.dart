import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/classes/soundboard_sound.dart';
import 'package:rift/data/repositories/server_session.dart';
import 'package:rift/data/repositories/session_repository.dart';
import 'package:rift/logic/cubits/app/app_cubit.dart';
import 'package:rift/logic/cubits/livekit/livekit_cubit.dart';
import 'package:rift/logic/cubits/server/server_cubit.dart';
import 'package:rift/logic/cubits/soundboard/soundboard_cubit.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/server_scope.dart';
import 'package:rift/presentation/screens/home/soundboard/soundboard_button.dart';

/// The call's soundboard card was an entry put straight on the overlay. A
/// route pushed later goes above the last route, not above such an entry, so
/// the Leave server dialog opened from the rail drew under the card, which
/// covered its words and its button; and the card heard neither Escape nor a
/// click that was not a plain tap.

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

/// Not in a call, so the button is about the scope's server.
class _StubLiveKitCubit extends Cubit<LiveKitState> implements LiveKitCubit {
  _StubLiveKitCubit() : super(const LiveKitState());

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubSoundboardCubit extends Cubit<SoundboardState>
    implements SoundboardCubit {
  _StubSoundboardCubit()
    : super(
        const SoundboardState(
          status: SoundboardStatus.ready,
          serverId: 'server',
          sounds: [
            SoundboardSound(
              id: 'chirp',
              name: 'chirp',
              objectPath: 'chirp.ogg',
              duration: Duration(seconds: 1),
              bytes: 1,
            ),
          ],
        ),
      );

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _card = find.text('SOUNDBOARD');

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => ThemeCubit()),
        BlocProvider(create: (_) => AppCubit()),
        BlocProvider<ServerCubit>(create: (_) => _StubServerCubit()),
        BlocProvider<LiveKitCubit>(create: (_) => _StubLiveKitCubit()),
        BlocProvider<SoundboardCubit>(create: (_) => _StubSoundboardCubit()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: ServerScope(
            server: ServerSession(SessionRepository(), 'server'),
            child: const Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.only(bottom: 40),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [SoundboardButton()],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.campaign_rounded));
  await tester.pumpAndSettle();
  expect(_card, findsOneWidget);
}

void main() {
  setUp(() => HydratedBloc.storage = _MemoryStorage());

  testWidgets('Escape closes the card', (tester) async {
    await _pump(tester);
    await _open(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(_card, findsNothing);
  });

  testWidgets('a press outside closes the card', (tester) async {
    await _pump(tester);
    await _open(tester);

    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(_card, findsNothing);

    // And the button opens it again, rather than thinking it still open.
    await _open(tester);
  });

  testWidgets('a dialog opened over the card is above it', (tester) async {
    await _pump(tester);
    await _open(tester);

    // What the rail's Leave server does while the card is up: a dialog,
    // here one big button, over the whole window.
    var pressed = false;
    final context = tester.element(_card);
    unawaited(
      showDialog<void>(
        context: context,
        useRootNavigator: true,
        builder: (_) => SizedBox.expand(
          child: TextButton(
            onPressed: () => pressed = true,
            child: const Text('Leave'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Where the card is: under it, the press reached the card instead.
    await tester.tapAt(tester.getCenter(_card));
    await tester.pump();
    expect(pressed, isTrue);
  });
}
