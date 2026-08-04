import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/search_dropdown_field.dart';

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

/// Records every query it is asked for, and only answers when told to — so a
/// test can inspect what the field does *while* a search is outstanding.
class _FakeSearch {
  final List<String> queries = [];
  final List<Completer<List<String>>> pending = [];

  Future<List<String>> call(String query) {
    queries.add(query);
    final completer = Completer<List<String>>();
    pending.add(completer);
    return completer.future;
  }

  void completeLast(List<String> results) => pending.last.complete(results);
}

Future<void> _pump(WidgetTester tester, _FakeSearch search) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: BlocProvider(
          create: (_) => ThemeCubit(),
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 260,
              child: SearchDropdownField<String>(
                hintText: 'Find…',
                emptyMessage: 'Nobody found.',
                onSearch: search.call,
                itemBuilder: (context, item, dismiss) =>
                    GestureDetector(onTap: dismiss, child: Text(item)),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUpAll(() => HydratedBloc.storage = _MemoryStorage());

  group('SearchDropdownField', () {
    testWidgets('says it is searching while the query is outstanding', (
      tester,
    ) async {
      final search = _FakeSearch();
      await _pump(tester, search);

      await tester.enterText(find.byType(TextField), 'ma');
      await tester.pump(const Duration(milliseconds: 300));

      // The whole point: an unanswered search reports itself rather than
      // leaving the drop-down blank or absent.
      expect(find.text('Searching…'), findsOneWidget);

      search.completeLast(['maya', 'marco']);
      await tester.pump();

      expect(find.text('Searching…'), findsNothing);
      expect(find.text('maya'), findsOneWidget);
      expect(find.text('marco'), findsOneWidget);
    });

    testWidgets('an empty answer says so rather than staying blank', (
      tester,
    ) async {
      final search = _FakeSearch();
      await _pump(tester, search);

      await tester.enterText(find.byType(TextField), 'zz');
      await tester.pump(const Duration(milliseconds: 300));
      search.completeLast(const []);
      await tester.pump();

      expect(find.text('Nobody found.'), findsOneWidget);
    });

    testWidgets('typing coalesces into one search, not one per keystroke', (
      tester,
    ) async {
      final search = _FakeSearch();
      await _pump(tester, search);

      await tester.enterText(find.byType(TextField), 'm');
      await tester.pump(const Duration(milliseconds: 50));
      await tester.enterText(find.byType(TextField), 'ma');
      await tester.pump(const Duration(milliseconds: 50));
      await tester.enterText(find.byType(TextField), 'may');
      await tester.pump(const Duration(milliseconds: 300));

      expect(search.queries, ['may']);

      search.completeLast(['maya']);
      await tester.pump();
    });

    testWidgets('a slow first answer cannot overwrite a newer one', (
      tester,
    ) async {
      final search = _FakeSearch();
      await _pump(tester, search);

      await tester.enterText(find.byType(TextField), 'ma');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byType(TextField), 'jo');
      await tester.pump(const Duration(milliseconds: 300));

      expect(search.queries, ['ma', 'jo']);

      // The stale "ma" request lands last; its results must not be shown.
      search.pending[1].complete(['jonas']);
      await tester.pump();
      search.pending[0].complete(['maya']);
      await tester.pump();

      expect(find.text('jonas'), findsOneWidget);
      expect(find.text('maya'), findsNothing);
    });

    testWidgets('clearing the field closes the drop-down', (tester) async {
      final search = _FakeSearch();
      await _pump(tester, search);

      await tester.enterText(find.byType(TextField), 'ma');
      await tester.pump(const Duration(milliseconds: 300));
      search.completeLast(['maya']);
      await tester.pump();
      expect(find.text('maya'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '');
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('maya'), findsNothing);
    });
  });
}
