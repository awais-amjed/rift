import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/context_menu/context_menu_button.dart';
import 'package:rift/presentation/common/nav_row.dart';
import 'package:rift/presentation/common/unread_badge.dart';

import 'helpers/memory_storage.dart';

Future<void> _pump(WidgetTester tester, Widget row) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: BlocProvider(
          create: (_) => ThemeCubit(),
          child: Center(child: SizedBox(width: 260, child: row)),
        ),
      ),
    ),
  );
  await tester.pump();
}

double _buttonOpacity(WidgetTester tester) => tester
    .widget<Opacity>(
      find.descendant(
        of: find.byType(ContextMenuButton),
        matching: find.byType(Opacity),
      ),
    )
    .opacity;

Future<void> _hover(WidgetTester tester, Finder target) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  addTearDown(mouse.removePointer);
  await mouse.addPointer(location: Offset.zero);
  await mouse.moveTo(tester.getCenter(target));
  await tester.pump();
}

/// The ••• that makes a row's right-click menu findable.
void main() {
  setUpAll(() => HydratedBloc.storage = MemoryStorage());

  const menu = Text('the menu');

  testWidgets('at rest the button holds its space but is not shown', (
    tester,
  ) async {
    await _pump(
      tester,
      const NavRow(icon: Icons.tag, label: 'general', overflowMenu: menu),
    );
    expect(find.byType(ContextMenuButton), findsOneWidget);
    expect(_buttonOpacity(tester), 0);
  });

  testWidgets('hovering the row shows it', (tester) async {
    await _pump(
      tester,
      NavRow(
        icon: Icons.tag,
        label: 'general',
        overflowMenu: menu,
        onTap: () {},
      ),
    );
    await _hover(tester, find.text('general'));
    expect(_buttonOpacity(tester), 1);
  });

  testWidgets('a selected row shows it without a pointer', (tester) async {
    await _pump(
      tester,
      const NavRow(
        icon: Icons.tag,
        label: 'general',
        isSelected: true,
        overflowMenu: menu,
      ),
    );
    expect(_buttonOpacity(tester), 1);
  });

  testWidgets('an unread count gives way to it on hover', (tester) async {
    await _pump(
      tester,
      NavRow(
        icon: Icons.tag,
        label: 'releases',
        overflowMenu: menu,
        trailing: const UnreadBadge(count: 4),
        onTap: () {},
      ),
    );
    expect(find.byType(UnreadBadge), findsOneWidget);
    await _hover(tester, find.text('releases'));
    expect(find.byType(UnreadBadge), findsNothing);
    expect(find.byType(ContextMenuButton), findsOneWidget);
  });

  testWidgets('a state icon stays, with the button after it', (tester) async {
    await _pump(
      tester,
      NavRow(
        icon: Icons.tag,
        label: 'incidents',
        overflowMenu: menu,
        trailing: const Icon(Icons.notifications_off_outlined),
        onTap: () {},
      ),
    );
    await _hover(tester, find.text('incidents'));
    expect(find.byIcon(Icons.notifications_off_outlined), findsOneWidget);
    expect(find.byType(ContextMenuButton), findsOneWidget);
  });

  testWidgets('pressing it opens the same menu', (tester) async {
    await _pump(
      tester,
      const NavRow(
        icon: Icons.tag,
        label: 'general',
        isSelected: true,
        overflowMenu: menu,
      ),
    );
    await tester.tap(find.byType(ContextMenuButton));
    await tester.pump();
    expect(find.text('the menu'), findsOneWidget);
  });

  testWidgets('no menu, no button', (tester) async {
    await _pump(tester, const NavRow(icon: Icons.tag, label: 'general'));
    expect(find.byType(ContextMenuButton), findsNothing);
  });
}
