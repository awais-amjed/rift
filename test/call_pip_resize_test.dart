import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rift/logic/cubits/app/app_cubit.dart';
import 'package:rift/logic/cubits/livekit/livekit_cubit.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/screens/home/call_pip/call_stream_pip.dart';
import 'package:rift/presentation/screens/home/call_pip/widgets/call_pip_card.dart';
import 'package:rift/presentation/screens/home/participants_grid/participants_tile/participant_name_badge.dart';

import 'support/memory_storage.dart';

/// In a call, watching one stream, and nothing else.
class _StubLiveKitCubit extends Cubit<LiveKitState> implements LiveKitCubit {
  _StubLiveKitCubit({Set<String> watching = const {'alice'}})
    : super(
        LiveKitState(
          connectionState: LiveKitConnectionState.connected,
          subscribedScreenshares: watching,
        ),
      );

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() => HydratedBloc.storage = MemoryStorage());

  Future<void> pumpPip(
    WidgetTester tester, {
    Set<String> watching = const {'alice'},
  }) async {
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<ThemeCubit>(create: (_) => ThemeCubit()),
          BlocProvider<AppCubit>(create: (_) => AppCubit()),
          BlocProvider<LiveKitCubit>(
            create: (_) => _StubLiveKitCubit(watching: watching),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: CallStreamPip())),
      ),
    );
    await tester.pumpAndSettle();
  }

  Rect card(WidgetTester tester) => tester.getRect(find.byType(CallPipCard));

  /// The mouse, in from outside the card and resting at [at].
  Future<TestGesture> hover(WidgetTester tester, Offset at) async {
    final mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      pointer: 1,
    );
    await mouse.addPointer(location: Offset.zero);
    await tester.pump();
    await mouse.moveTo(card(tester).center);
    await tester.pump();
    await mouse.moveTo(at);
    await tester.pump();
    return mouse;
  }

  /// [mouse], resting at [at], pressed and pulled [step] six times, a frame
  /// each, past the drag slop: the resize is under way.
  Future<void> pull(
    WidgetTester tester,
    TestGesture mouse,
    Offset at, {
    Offset step = const Offset(-5, 0),
  }) async {
    await mouse.down(at);
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await mouse.moveBy(step);
      await tester.pump();
    }
  }

  /// The corner that moves, of a card resting bottom right: its top left,
  /// and left is bigger.
  Future<TestGesture> grab(WidgetTester tester) async {
    await pumpPip(tester);
    final grip = card(tester).topLeft + const Offset(2, 2);
    final mouse = await hover(tester, grip);
    await pull(tester, mouse, grip);
    return mouse;
  }

  MouseCursor cursor() =>
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1)!;

  double width(WidgetTester tester) =>
      tester.getSize(find.byType(CallPipCard)).width;

  testWidgets('the grip keeps up with a mouse that moves between frames', (
    tester,
  ) async {
    final mouse = await grab(tester);
    final started = width(tester);
    // A mouse reports several moves a frame: five with no frame between.
    for (var i = 0; i < 5; i++) {
      await mouse.moveBy(const Offset(-10, 0));
    }
    await tester.pump();

    expect(started, greaterThan(320));
    expect(width(tester), closeTo(started + 50, 0.5));
    await mouse.up();
    await tester.pumpAndSettle();
  });

  testWidgets('its side facing in resizes it, with the arrows for it', (
    tester,
  ) async {
    await pumpPip(tester);
    final before = card(tester);
    final edge = before.centerLeft + const Offset(2, 0);
    final mouse = await hover(tester, edge);
    expect(cursor(), SystemMouseCursors.resizeLeftRight);
    await pull(tester, mouse, edge);
    final started = card(tester).width;
    await mouse.moveBy(const Offset(-40, 0));
    await tester.pump();

    expect(started, greaterThan(before.width));
    expect(card(tester).width, closeTo(started + 40, 0.5));
    // Its corner stays put.
    expect(card(tester).bottomRight, before.bottomRight);
    await mouse.up();
    await tester.pumpAndSettle();
  });

  testWidgets('its top facing in resizes it, with the arrows for it', (
    tester,
  ) async {
    await pumpPip(tester);
    final before = card(tester);
    final edge = before.topCenter + const Offset(0, 2);
    final mouse = await hover(tester, edge);
    expect(cursor(), SystemMouseCursors.resizeUpDown);
    await pull(tester, mouse, edge, step: const Offset(0, -5));
    final started = card(tester).height;
    await mouse.moveBy(const Offset(0, -20));
    await tester.pump();

    expect(started, greaterThan(before.height));
    expect(card(tester).height, closeTo(started + 20, 0.5));
    expect(card(tester).bottomRight, before.bottomRight);
    await mouse.up();
    await tester.pumpAndSettle();
  });

  testWidgets('the sides by its corner move it, as before', (tester) async {
    await pumpPip(tester);
    final mouse = await hover(
      tester,
      card(tester).centerRight - const Offset(2, 0),
    );
    expect(cursor(), SystemMouseCursors.grab);
    await mouse.removePointer();
  });

  testWidgets('its corner resizes it, with no grip drawn on it', (
    tester,
  ) async {
    await pumpPip(tester);
    await hover(tester, card(tester).topLeft + const Offset(2, 2));
    expect(cursor(), SystemMouseCursors.resizeUpLeftDownRight);
    expect(find.byIcon(Icons.open_in_full_rounded), findsNothing);
  });

  testWidgets('whose stream it is shows along its top, hovered or not', (
    tester,
  ) async {
    await pumpPip(tester);
    final badge = find.byType(ParticipantNameBadge);
    expect(badge, findsOneWidget);
    expect(tester.getRect(badge).top, lessThan(card(tester).center.dy));
    final fades = tester.widgetList<AnimatedOpacity>(
      find.ancestor(of: badge, matching: find.byType(AnimatedOpacity)),
    );
    expect(fades.every((f) => f.opacity == 1), isTrue);
  });

  /// One step of a window being dragged larger or smaller.
  Future<void> resizeWindow(WidgetTester tester, Size to) async {
    tester.view.physicalSize = to;
    await tester.pump();
  }

  testWidgets('a window being resized moves it at once, with nothing left '
      'animating', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.reset);
    await pumpPip(tester);
    final gap = const Offset(1200, 800) - card(tester).bottomRight;

    await resizeWindow(tester, const Size(1100, 760));

    // Already in its corner of the new pane: a slide would restart on every
    // step of the drag and ask for a frame on every vsync while it lasted.
    expect(card(tester).bottomRight, const Offset(1100, 760) - gap);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('with no stream to show, a resize starts nothing either', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.reset);
    await pumpPip(tester, watching: const {});
    expect(find.byType(CallPipCard), findsNothing);

    for (final width in [1150.0, 1100.0, 1050.0]) {
      await resizeWindow(tester, Size(width, 800));
      expect(tester.binding.hasScheduledFrame, isFalse);
    }
  });
}
