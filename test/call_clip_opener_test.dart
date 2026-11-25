import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rift/data/classes/call_clip_audio.dart';
import 'package:rift/logic/cubits/app/app_cubit.dart';
import 'package:rift/logic/cubits/livekit/livekit_cubit.dart';
import 'package:rift/logic/cubits/screenshare/screenshare_cubit.dart';
import 'package:rift/logic/cubits/server/server_cubit.dart';
import 'package:rift/logic/cubits/soundboard/soundboard_cubit.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/logic/cubits/voice_stats/voice_stats_cubit.dart';
import 'package:rift/logic/visibility/app_seen_listener.dart';
import 'package:rift/presentation/screens/home/call_clip/call_clip_dialog.dart';
import 'package:rift/presentation/screens/home/call_clip/call_clip_opener.dart';

import 'support/memory_storage.dart';

/// A clip taken behind a game waits for Rift to be seen. The trim view was
/// pushed from `didChangeDependencies`, inside the build that told the
/// opener, which a debug build refuses ("setState() or markNeedsBuild()
/// called during build"): the clip was taken off the queue and no trim view
/// opened again that run.

class _StubLiveKitCubit extends Cubit<LiveKitState> implements LiveKitCubit {
  _StubLiveKitCubit() : super(const LiveKitState());

  void clipped(CallClipAudio clip) =>
      emit(state.copyWith(pendingClips: [clip]));

  @override
  void setAppSeen(bool seen) {}

  @override
  void takeClip(int id) => emit(
    state.copyWith(
      pendingClips: [
        for (final clip in state.pendingClips)
          if (clip.id != id) clip,
      ],
    ),
  );

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubScreenshareCubit extends Cubit<ScreenshareState>
    implements ScreenshareCubit {
  _StubScreenshareCubit() : super(const ScreenshareState());

  @override
  void setAppSeen(bool seen) {}

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubServerCubit extends Cubit<ServerState> implements ServerCubit {
  _StubServerCubit() : super(const ServerState());

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubSoundboardCubit extends Cubit<SoundboardState>
    implements SoundboardCubit {
  _StubSoundboardCubit() : super(const SoundboardState());

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _seenChannel = EventChannel('rift/window_seen');

void main() {
  setUp(() => HydratedBloc.storage = MemoryStorage());

  testWidgets('a clip taken unseen opens once Rift is seen', (tester) async {
    // The runner's word on the window, as on Windows behind a game: frames
    // go on (a hidden lifecycle would stop them, and nothing would be built
    // unseen at all).
    MockStreamHandlerEventSink? seen;
    tester.binding.defaultBinaryMessenger.setMockStreamHandler(
      _seenChannel,
      MockStreamHandler.inline(
        onListen: (_, events) {
          seen = events;
        },
      ),
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockStreamHandler(
        _seenChannel,
        null,
      ),
    );
    final livekit = _StubLiveKitCubit();
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider(create: (_) => ThemeCubit()),
          BlocProvider(create: (_) => AppCubit()),
          BlocProvider<ServerCubit>(create: (_) => _StubServerCubit()),
          BlocProvider<LiveKitCubit>.value(value: livekit),
          BlocProvider(create: (_) => VoiceStatsCubit(livekitCubit: livekit)),
          BlocProvider<ScreenshareCubit>(
            create: (_) => _StubScreenshareCubit(),
          ),
          BlocProvider<SoundboardCubit>(create: (_) => _StubSoundboardCubit()),
        ],
        // As the app has it: the listener round the whole app.
        child: const AppSeenListener(
          child: MaterialApp(
            home: CallClipOpener(child: Scaffold(body: SizedBox())),
          ),
        ),
      ),
    );
    await tester.pump();

    // Hidden behind a game, the shortcut takes a clip: it waits.
    seen!.success(false);
    await tester.pump();
    await tester.pump();
    livekit.clipped(
      CallClipAudio(
        id: 1,
        pcm: Int16List(48000 * 2),
        rate: 48000,
        channels: 2,
        at: DateTime(2026, 11, 21),
      ),
    );
    await tester.pump();
    expect(find.byType(CallClipDialog), findsNothing);
    expect(livekit.state.pendingClips, hasLength(1));

    // The game goes: the trim view opens.
    seen!.success(true);
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(CallClipDialog), findsOneWidget);
    expect(livekit.state.pendingClips, isEmpty);
  });
}
