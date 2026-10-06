import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/classes/chat_message.dart';
import 'package:rift/logic/cubits/app/app_cubit.dart';
import 'package:rift/logic/cubits/server_members/server_members_cubit.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/chat/message_row/chat_message_row.dart';

import 'support/memory_storage.dart';
import 'support/stub_members_cubit.dart';

/// Selecting a message used to need the press to land on its letters: the
/// body was a `SelectableText`, which answers only inside the box its words
/// fill, so a drag begun in the row's margin or beside a short line did
/// nothing. The row is the selection region now.
void main() {
  setUpAll(() => HydratedBloc.storage = MemoryStorage());

  final msg = ChatMessage(
    id: 'm1',
    authorId: 'them',
    authorName: 'Them',
    text: 'hello there',
    sentAt: DateTime.utc(2026, 1, 1),
    isMine: false,
  );

  Future<void> pumpRow(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: MultiBlocProvider(
          providers: [
            BlocProvider<ThemeCubit>(create: (_) => ThemeCubit()),
            BlocProvider<AppCubit>(create: (_) => AppCubit()),
            BlocProvider<ServerMembersCubit>(
              create: (_) => StubMembersCubit(),
            ),
          ],
          child: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: ChatMessageRow(
                message: msg,
                showHeader: true,
                onToggleReaction: (_, _) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// What the next Ctrl+C puts on the clipboard.
  String? copied;
  setUp(() => copied = null);

  void watchClipboard(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
  }

  Future<void> copy(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  Future<void> mouseDrag(WidgetTester tester, Offset from, Offset to) async {
    final gesture = await tester.startGesture(
      from,
      kind: PointerDeviceKind.mouse,
    );
    for (var i = 1; i <= 10; i++) {
      await gesture.moveTo(Offset.lerp(from, to, i / 10)!);
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();
  }

  testWidgets(
    'a drag from the margin to past the end takes the whole message',
    (tester) async {
      await pumpRow(tester);
      watchClipboard(tester);
      final text = tester.getRect(find.textContaining('hello there'));
      final row = tester.getRect(find.byType(ChatMessageRow));

      // From the row's left edge, level with the text, to well right of the
      // last letter: neither end is on a glyph.
      await mouseDrag(
        tester,
        Offset(row.left + 2, text.center.dy),
        Offset(text.right + 200, text.center.dy),
      );
      await copy(tester);

      expect(copied, 'hello there');
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'a drag from beside the last word back to the margin does too',
    (tester) async {
      await pumpRow(tester);
      watchClipboard(tester);
      final text = tester.getRect(find.textContaining('hello there'));
      final row = tester.getRect(find.byType(ChatMessageRow));

      await mouseDrag(
        tester,
        Offset(text.right + 200, text.center.dy),
        Offset(row.left + 2, text.center.dy),
      );
      await copy(tester);

      expect(copied, 'hello there');
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'a right-click on the text opens the message menu, once',
    (tester) async {
      await pumpRow(tester);
      final text = tester.getCenter(find.textContaining('hello there'));
      final gesture = await tester.startGesture(
        text,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryButton,
      );
      // Held as a real click is, past the tap's deadline.
      await tester.pump(const Duration(milliseconds: 150));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('Copy text'), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
}
