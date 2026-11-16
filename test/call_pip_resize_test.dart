import 'package:flutter/gestures.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rift/logic/cubits/app/app_cubit.dart';
import 'package:rift/logic/cubits/livekit/livekit_cubit.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/screens/home/call_pip/call_stream_pip.dart';
import 'package:rift/presentation/screens/home/call_pip/widgets/call_pip_card.dart';

import 'support/memory_storage.dart';

/// In a call, watching one stream, and nothing else.
class _StubLiveKitCubit extends Cubit<LiveKitState> implements LiveKitCubit {
  _StubLiveKitCubit()
    : super(
        const LiveKitState(
          connectionState: LiveKitConnectionState.connected,
          subscribedScreenshares: {'alice'},
        ),
      );

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() => HydratedBloc.storage = MemoryStorage());

  testWidgets('the grip keeps up with a mouse that moves between frames', (
    tester,
  ) async {
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<ThemeCubit>(create: (_) => ThemeCubit()),
          BlocProvider<AppCubit>(create: (_) => AppCubit()),
          BlocProvider<LiveKitCubit>(create: (_) => _StubLiveKitCubit()),
        ],
        child: const MaterialApp(home: Scaffold(body: CallStreamPip())),
      ),
    );
    await tester.pumpAndSettle();

    final card = find.byType(CallPipCard);
    final before = tester.getSize(card).width;

    // Hovered, so the grip shows.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await tester.pump();
    await mouse.moveTo(tester.getCenter(card));
    await tester.pump();
    await mouse.moveTo(
      tester.getCenter(find.byIcon(Icons.open_in_full_rounded)),
    );
    await tester.pump();

    // Resting bottom right, the grip is top left: left is bigger.
    await mouse.down(tester.getCenter(find.byIcon(Icons.open_in_full_rounded)));
    await tester.pump();
    // Past the drag slop, a frame at a time, so the resize is under way.
    for (var i = 0; i < 6; i++) {
      await mouse.moveBy(const Offset(-5, 0));
      await tester.pump();
    }
    final started = tester.getSize(card).width;
    // A mouse reports several moves a frame: five with no frame between.
    for (var i = 0; i < 5; i++) {
      await mouse.moveBy(const Offset(-10, 0));
    }
    await tester.pump();

    expect(started, greaterThan(before));
    expect(tester.getSize(card).width, closeTo(started + 50, 0.5));
    await mouse.up();
    await tester.pumpAndSettle();
  });
}
