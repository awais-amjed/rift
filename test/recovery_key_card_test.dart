import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/screens/recovery_key/widgets/recovery_key_card.dart';

import 'helpers/memory_storage.dart';

const _key = 'ABCDE-FGHJK-LMNPQ-RSTUV-WXYZ2';

Future<void> _pump(WidgetTester tester, {required double textScale}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: BlocProvider(
            create: (_) => ThemeCubit(),
            // Scrolled, as the screen is: only the width is under test.
            child: const SingleChildScrollView(
              child: Center(
                child: SizedBox(
                  width: 320,
                  child: RecoveryKeyCard(recoveryKey: _key),
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

/// The key's groups are shared evenly between lines. Laid out in rows rather
/// than a wrap, a group wider than the card on its own — the largest system
/// text on a phone — could run off the edge.
void main() {
  setUpAll(() => HydratedBloc.storage = MemoryStorage());

  testWidgets('every group is on screen at the normal size', (tester) async {
    await _pump(tester, textScale: 1);
    expect(tester.takeException(), isNull);
    for (final group in _key.split('-')) {
      expect(find.text(group), findsOneWidget);
    }
  });

  testWidgets('a group wider than the card does not overflow it', (
    tester,
  ) async {
    await _pump(tester, textScale: 4);
    expect(tester.takeException(), isNull);
  });
}
