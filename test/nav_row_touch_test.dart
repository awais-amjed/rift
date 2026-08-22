import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/constants.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/nav_row.dart';

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

/// The row the whole app is navigated with — channels, DM conversations, the
/// settings sections. It is sized by its padding rather than a fixed height,
/// which is what let it come out at 32px: comfortable under a cursor, and a
/// miss under a thumb.
///
/// The window's width is what decides, not the platform: a desktop window
/// dragged to phone width is being used with a mouse and does not need this,
/// but it costs nothing there and getting it from the same signal as every
/// other responsive decision is worth more than the pixels saved.
void main() {
  setUpAll(() => HydratedBloc.storage = _MemoryStorage());

  Future<double> rowHeight(WidgetTester tester, double windowWidth) async {
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: Size(windowWidth, 800)),
        child: MaterialApp(
          home: BlocProvider(
            create: (_) => ThemeCubit(),
            child: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 240,
                  child: NavRow(
                    icon: Icons.tag_rounded,
                    label: 'general',
                    onTap: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return tester.getSize(find.byType(NavRow)).height;
  }

  testWidgets('reaches the touch minimum on a phone', (tester) async {
    expect(
      await rowHeight(tester, 390),
      greaterThanOrEqualTo(K.touchTargetMin),
    );
  });

  testWidgets('is left at its designed height on a desktop', (tester) async {
    // Not merely "smaller": the desktop row is a deliberate density and this
    // must not quietly become the app's row height everywhere.
    final wide = await rowHeight(tester, 1400);
    expect(wide, lessThan(K.touchTargetMin));
    expect(wide, greaterThan(28));
  });

  testWidgets('grows at the breakpoint, not before it', (tester) async {
    expect(
      await rowHeight(tester, K.breakpointMedium),
      lessThan(K.touchTargetMin),
    );
    expect(
      await rowHeight(tester, K.breakpointMedium - 1),
      greaterThanOrEqualTo(K.touchTargetMin),
    );
  });
}
