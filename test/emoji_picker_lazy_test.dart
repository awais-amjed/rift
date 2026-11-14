import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rift/logic/cubits/app/app_cubit.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/chat/composer/emoji_picker_cell.dart';
import 'package:rift/presentation/common/chat/composer/emoji_picker_panel.dart';

import 'support/memory_storage.dart';

/// The emoji picker builds only the rows on screen, and its category icons
/// still land each category's heading at the top of the grid: the jump sums
/// fixed row heights rather than asking a section that may not be built yet.
void main() {
  setUp(() => HydratedBloc.storage = MemoryStorage());

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [ThemeState()]),
        home: BlocProvider(
          create: (_) => AppCubit(),
          child: Scaffold(body: EmojiPickerPanel(onSelected: (_) {})),
        ),
      ),
    );
    // The set loads after the first frame; the dots animate until it does.
    for (
      var i = 0;
      i < 20 && find.byType(EmojiPickerCell).evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

  testWidgets('builds only the rows on screen', (tester) async {
    await open(tester);
    final built = find.byType(EmojiPickerCell).evaluate().length;
    expect(built, greaterThan(0));
    // The panel is 320 high: a handful of 34-pixel rows of 8, with the cache
    // area either side, nowhere near the thousands in the set.
    expect(built, lessThan(120));
  });

  testWidgets('a category icon brings its heading to the top', (tester) async {
    await open(tester);
    final grid = tester.getTopLeft(find.byType(CustomScrollView));
    for (final (icon, heading) in [
      (Icons.flag, 'Flags'),
      (Icons.flight, 'Travel & places'),
      (Icons.mood, 'Smileys & people'),
    ]) {
      await tester.tap(find.byIcon(icon));
      await tester.pumpAndSettle();
      final at = tester.getTopLeft(find.text(heading));
      // The heading sits in a 26-high row, under the grid's 10 of padding.
      expect(at.dy - grid.dy, inInclusiveRange(10, 10 + 26), reason: heading);
    }
  });
}
