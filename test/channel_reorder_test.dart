import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/classes/channel.dart';
import 'package:rift/data/enums/channel_type.dart';
import 'package:rift/logic/cubits/server/server_cubit.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/screens/home/channels/channel_list/widgets/channel_section.dart';
import 'package:toastification/toastification.dart';

import 'support/memory_storage.dart';

/// Records each reorder and answers when the test says so.
class _StubServerCubit extends Cubit<ServerState> implements ServerCubit {
  _StubServerCubit() : super(const ServerState());

  final List<List<String>> asked = [];
  Completer<({bool success, String? error})>? answer;

  @override
  Future<({bool success, String? error})> reorderChannels(
    List<String> channelIds,
  ) {
    asked.add(channelIds);
    return (answer = Completer()).future;
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Channel _ch(String name) =>
    Channel(id: 'id-$name', name: name, channelType: ChannelType.text);

/// The rows' names, top to bottom.
List<String> _order(WidgetTester tester) {
  double top(String name) => tester.getTopLeft(find.text(name)).dy;
  return ['a', 'b', 'c']..sort((x, y) => top(x).compareTo(top(y)));
}

Future<void> _pump(
  WidgetTester tester,
  _StubServerCubit cubit,
  List<Channel> channels, {
  bool canReorder = true,
}) => tester.pumpWidget(
  MultiBlocProvider(
    providers: [
      BlocProvider<ThemeCubit>(create: (_) => ThemeCubit()),
      BlocProvider<ServerCubit>.value(value: cubit),
    ],
    child: ToastificationWrapper(
      child: MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              ChannelSection(
                channels: channels,
                canReorder: canReorder,
                rowBuilder: (context, ch, grip) =>
                    grip(SizedBox(height: 40, child: Text(ch.name))),
              ),
            ],
          ),
        ),
      ),
    ),
  ),
);

/// Picks up [name] and carries it down by [dy], a step at a time, the way
/// a hand does.
Future<void> _drag(WidgetTester tester, String name, double dy) async {
  final gesture = await tester.startGesture(tester.getCenter(find.text(name)));
  for (var i = 0; i < 10; i++) {
    await gesture.moveBy(Offset(0, dy / 10));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => HydratedBloc.storage = MemoryStorage());

  final abc = [_ch('a'), _ch('b'), _ch('c')];

  testWidgets('a drop asks the server, and shows its order until it answers', (
    tester,
  ) async {
    final cubit = _StubServerCubit();
    await _pump(tester, cubit, abc);
    expect(_order(tester), ['a', 'b', 'c']);

    await _drag(tester, 'a', 100);

    expect(cubit.asked, [
      ['id-b', 'id-c', 'id-a'],
    ]);
    expect(_order(tester), ['b', 'c', 'a']);

    // The server's list arrives in the dropped order, then the call returns.
    await _pump(tester, cubit, [abc[1], abc[2], abc[0]]);
    cubit.answer!.complete((success: true, error: null));
    await tester.pumpAndSettle();
    expect(_order(tester), ['b', 'c', 'a']);
  });

  testWidgets('a refused drop puts the rows back', (tester) async {
    final cubit = _StubServerCubit();
    await _pump(tester, cubit, abc);

    await _drag(tester, 'a', 100);
    expect(_order(tester), ['b', 'c', 'a']);

    cubit.answer!.complete((success: false, error: 'No'));
    await tester.pumpAndSettle();
    expect(_order(tester), ['a', 'b', 'c']);
    expect(find.text('No'), findsOneWidget);
    // The refusal is a toast; let it time out before the tree goes.
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
  });

  testWidgets('a member cannot pick a row up', (tester) async {
    final cubit = _StubServerCubit();
    await _pump(tester, cubit, abc, canReorder: false);

    await _drag(tester, 'a', 100);

    expect(cubit.asked, isEmpty);
    expect(_order(tester), ['a', 'b', 'c']);
  });
}
