import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/screens/home/dms/widgets/dm_chat_header.dart';

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

const double _headerWidth = 640;

Future<void> _pumpHeader(WidgetTester tester, String title) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: BlocProvider(
          create: (_) => ThemeCubit(),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: _headerWidth,
              child: DmChatHeader(
                title: title,
                tierLabel: 'Central',
                tierIcon: Icons.public,
                onClose: () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// A `Flexible` title and a `Spacer` in the same row divide the free space
/// between them, so a short title left half the bar unused *after* the close
/// button — parking it in the middle of the header instead of at its edge.
void main() {
  setUpAll(() => HydratedBloc.storage = _MemoryStorage());

  group('DmChatHeader layout', () {
    /// Header padding plus the button's own centring; anything beyond this is
    /// the title's unclaimed flex leaking out.
    const slack = 32.0;

    testWidgets('the close button hugs the right edge for a short title', (
      tester,
    ) async {
      await _pumpHeader(tester, '@a');

      final close = tester.getRect(find.byIcon(Icons.close_rounded));
      expect(_headerWidth - close.right, lessThan(slack));
    });

    testWidgets('and for a title long enough to need truncating', (
      tester,
    ) async {
      await _pumpHeader(
        tester,
        '@an-extremely-long-handle-that-cannot-possibly-fit-in-the-bar',
      );

      final close = tester.getRect(find.byIcon(Icons.close_rounded));
      expect(_headerWidth - close.right, lessThan(slack));
    });

    testWidgets('the title never overruns the controls', (tester) async {
      await _pumpHeader(
        tester,
        '@an-extremely-long-handle-that-cannot-possibly-fit-in-the-bar',
      );

      final title = tester.getRect(
        find.text(
          '@an-extremely-long-handle-that-cannot-possibly-fit-in-the-bar',
        ),
      );
      final close = tester.getRect(find.byIcon(Icons.close_rounded));
      expect(title.right, lessThanOrEqualTo(close.left));
    });
  });
}
