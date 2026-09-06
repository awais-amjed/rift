import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/classes/dm_conversation.dart';
import 'package:rift/data/enums/layout_mode.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/screens/home/dms/widgets/dm_list_panel.dart';

import 'shell_scope_harness.dart';

/// In-memory stand-in so [ThemeCubit] (a HydratedCubit) can be built in tests.
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

/// The server-DM list pages (`011_directory.sql`), and the panel is the half of that
/// nobody notices until it is wrong: a footer that never appears makes a list
/// that has more behind it look finished, and a scroll that never asks makes
/// the cursor decorative.
void main() {
  setUpAll(() => HydratedBloc.storage = _MemoryStorage());

  List<DmConversation> conversations(int count) => [
    for (var i = 0; i < count; i++)
      DmConversation(peerId: 'peer-$i', peerName: 'Peer $i'),
  ];

  Future<void> pump(
    WidgetTester tester, {
    required List<DmConversation> rows,
    required bool hasMore,
    Future<void> Function()? onLoadMore,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider(
          create: (_) => ThemeCubit(),
          child: withShellScope(
            mode: LayoutMode.expanded,
            Scaffold(
              body: SizedBox(
                width: 280,
                height: 400,
                child: DmListPanel(
                  title: 'Server DMs',
                  conversations: rows,
                  hasMore: hasMore,
                  onLoadMore: onLoadMore,
                  onOpen: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a list with more behind it says so', (tester) async {
    await pump(tester, rows: conversations(3), hasMore: true);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('and a finished one does not', (tester) async {
    // The distinction the spinner draws is "there is more coming", not "this
    // is the end of a short list" — a permanent spinner under three rows reads
    // as a list that never loaded.
    await pump(tester, rows: conversations(3), hasMore: false);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('scrolling near the bottom asks for the next page', (
    tester,
  ) async {
    var asked = 0;
    await pump(
      tester,
      rows: conversations(30),
      hasMore: true,
      onLoadMore: () async => asked++,
    );
    expect(asked, 0, reason: 'a list at rest should not fetch');

    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pump();
    expect(asked, greaterThan(0));
  });

  testWidgets('a list that has reached the end never asks', (tester) async {
    var asked = 0;
    await pump(
      tester,
      rows: conversations(30),
      hasMore: false,
      onLoadMore: () async => asked++,
    );
    await tester.drag(find.byType(ListView), const Offset(0, -2000));
    await tester.pump();
    expect(asked, 0);
  });
}
