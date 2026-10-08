import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/classes/api_response.dart';
import 'package:rift/data/classes/channel.dart';
import 'package:rift/data/classes/server.dart';
import 'package:rift/data/enums/channel_type.dart';
import 'package:rift/data/repositories/server_repository.dart';
import 'package:rift/data/repositories/session_repository.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/screens/home/channels/channel_list/widgets/channel_section.dart';
import 'package:toastification/toastification.dart';

import 'support/memory_storage.dart';

/// Records each reorder and answers when the test says so. The re-read that
/// follows fails, so nothing else moves.
class _StubServers extends ServerRepository {
  final List<List<String>> asked = [];
  Completer<APIResponse>? answer;

  @override
  Future<APIResponse> reorderChannels(
    String supabaseUrl,
    List<String> channelIds, {
    required String anonKey,
    String? bearerToken,
  }) {
    asked.add(channelIds);
    return (answer = Completer()).future;
  }

  @override
  Future<APIResponse> getServerDetails(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
  }) async => APIResponse.error('offline');
}

SessionRepository _session(_StubServers servers) =>
    SessionRepository(servers: servers)..publish(
      servers: [
        Server(
          id: 's1',
          name: 'Test',
          supabaseUrl: 'https://server.invalid',
          token: 't',
        ),
      ],
      selectedServerId: 's1',
    );

Channel _ch(String name) =>
    Channel(id: 'id-$name', name: name, channelType: ChannelType.text);

/// The rows' names, top to bottom.
List<String> _order(WidgetTester tester) {
  double top(String name) => tester.getTopLeft(find.text(name)).dy;
  return ['a', 'b', 'c']..sort((x, y) => top(x).compareTo(top(y)));
}

Future<void> _pump(
  WidgetTester tester,
  _StubServers servers,
  List<Channel> channels, {
  bool canReorder = true,
}) => tester.pumpWidget(
  RepositoryProvider<SessionRepository>.value(
    value: _session(servers),
    child: BlocProvider<ThemeCubit>(
      create: (_) => ThemeCubit(),
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
    final servers = _StubServers();
    await _pump(tester, servers, abc);
    expect(_order(tester), ['a', 'b', 'c']);

    await _drag(tester, 'a', 100);

    expect(servers.asked, [
      ['id-b', 'id-c', 'id-a'],
    ]);
    expect(_order(tester), ['b', 'c', 'a']);

    // The server's list arrives in the dropped order, then the call returns.
    await _pump(tester, servers, [abc[1], abc[2], abc[0]]);
    servers.answer!.complete(APIResponse.success(const {}));
    await tester.pumpAndSettle();
    expect(_order(tester), ['b', 'c', 'a']);
  });

  testWidgets('a refused drop puts the rows back', (tester) async {
    final servers = _StubServers();
    await _pump(tester, servers, abc);

    await _drag(tester, 'a', 100);
    expect(_order(tester), ['b', 'c', 'a']);

    servers.answer!.complete(APIResponse.error('No'));
    await tester.pumpAndSettle();
    expect(_order(tester), ['a', 'b', 'c']);
    expect(find.text("Couldn't reorder the channels"), findsOneWidget);
    // The refusal is a toast; let it time out before the tree goes.
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
  });

  testWidgets('a member cannot pick a row up', (tester) async {
    final servers = _StubServers();
    await _pump(tester, servers, abc, canReorder: false);

    await _drag(tester, 'a', 100);

    expect(servers.asked, isEmpty);
    expect(_order(tester), ['a', 'b', 'c']);
  });
}
