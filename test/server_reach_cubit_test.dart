import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/cubits/server_reach/server_reach_cubit.dart';

void main() {
  const settle = Duration(milliseconds: 40);
  const longer = Duration(milliseconds: 80);
  const winTest = (id: 's1', name: 'Win Test');
  const other = (id: 's2', name: 'Other');

  late ValueNotifier<Set<String>> down;
  late StreamController<({String id, String name})?> selected;

  ServerReachCubit cubit({({String id, String name})? initial = winTest}) =>
      ServerReachCubit(
        unreachable: down,
        selected: selected.stream,
        initial: initial,
        settle: settle,
      );

  setUp(() {
    down = ValueNotifier(const {});
    selected = StreamController.broadcast();
  });
  tearDown(() => selected.close());

  test('the selected server down past the settle is named', () async {
    final c = cubit();
    down.value = {'s1'};
    await Future<void>.delayed(Duration.zero);
    expect(c.state.unreachableName, isNull, reason: 'not before the settle');
    await Future<void>.delayed(longer);
    expect(c.state.unreachableName, 'Win Test');
    await c.close();
  });

  test('a drop shorter than the settle never shows', () async {
    final c = cubit();
    down.value = {'s1'};
    await Future<void>.delayed(settle ~/ 4);
    down.value = const {};
    await Future<void>.delayed(longer);
    expect(c.state.unreachableName, isNull);
    await c.close();
  });

  test('coming back is reported at once', () async {
    final c = cubit();
    down.value = {'s1'};
    await Future<void>.delayed(longer);
    expect(c.state.unreachableName, 'Win Test');
    down.value = const {};
    expect(c.state.unreachableName, isNull);
    await c.close();
  });

  test('a server that is not selected is never named', () async {
    final c = cubit();
    down.value = {'s2'};
    await Future<void>.delayed(longer);
    expect(c.state.unreachableName, isNull);
    await c.close();
  });

  test(
    'switching to a server that has long been down names it at once',
    () async {
      final c = cubit();
      down.value = {'s2'};
      await Future<void>.delayed(longer);
      selected.add(other);
      await Future<void>.delayed(Duration.zero);
      expect(c.state.unreachableName, 'Other');
      // And switching away from it clears it.
      selected.add(winTest);
      await Future<void>.delayed(Duration.zero);
      expect(c.state.unreachableName, isNull);
      await c.close();
    },
  );

  test('with no server selected there is nothing to name', () async {
    final c = cubit(initial: null);
    down.value = {'s1', 's2'};
    await Future<void>.delayed(longer);
    expect(c.state.unreachableName, isNull);
    await c.close();
  });
}
