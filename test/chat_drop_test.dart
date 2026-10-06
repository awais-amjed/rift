import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/logic/cubits/app/app_cubit.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/chat/composer/chat_composer.dart';
import 'package:rift/presentation/common/chat/composer/composer_staged_chip.dart';
import 'package:rift/presentation/common/chat/drop/chat_drop_relay.dart';
import 'package:toastification/toastification.dart';

import 'support/memory_storage.dart';

DroppedFile _file(String name, int size) =>
    (name: name, bytes: Uint8List(size), mimeType: 'text/plain');

/// A composer under [relay], the way a chat pane's drop zone puts it.
Future<void> _pump(
  WidgetTester tester,
  ChatDropRelay relay, {
  bool canAttach = true,
  int maxBytes = 1000,
}) async {
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<ThemeCubit>(create: (_) => ThemeCubit()),
        BlocProvider<AppCubit>(create: (_) => AppCubit()),
      ],
      child: ToastificationWrapper(
        child: MaterialApp(
          home: Scaffold(
            body: ChatDropScope(
              relay: relay,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: ChatComposer(
                  onSend: (_, _, _) async => false,
                  canAttach: canAttach,
                  maxAttachmentBytes: maxBytes,
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

/// Delivers [files] and lets the composer read and stage them.
Future<void> _drop(
  WidgetTester tester,
  ChatDropRelay relay,
  List<DroppedFile> files,
) async {
  relay.deliver(files);
  await tester.pumpAndSettle();
}

/// The names on the staged chips, in order.
List<String> _staged(WidgetTester tester) => tester
    .widgetList<ComposerStagedChip>(find.byType(ComposerStagedChip))
    .map((c) => c.attachment.name)
    .toList();

void main() {
  setUpAll(() => HydratedBloc.storage = MemoryStorage());

  group('dropping files on a chat pane', () {
    testWidgets('they are staged in the composer below it', (tester) async {
      final relay = ChatDropRelay();
      await _pump(tester, relay);
      expect(relay.accepts, isTrue);

      await _drop(tester, relay, [
        _file('notes.txt', 10),
        _file('todo.txt', 10),
      ]);

      expect(_staged(tester), ['notes.txt', 'todo.txt']);
    });

    testWidgets('a file too big is refused, the rest still go', (tester) async {
      final relay = ChatDropRelay();
      await _pump(tester, relay);

      await _drop(tester, relay, [
        _file('huge.txt', 5000),
        _file('small.txt', 10),
      ]);

      expect(_staged(tester), ['small.txt']);
      // The refusal is a toast; let it time out before the tree goes.
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
    });

    testWidgets('a composer that may not attach takes nothing', (tester) async {
      final relay = ChatDropRelay();
      await _pump(tester, relay, canAttach: false);
      expect(relay.accepts, isFalse);

      await _drop(tester, relay, [_file('notes.txt', 10)]);
      expect(_staged(tester), isEmpty);
    });

    testWidgets('a pane with no composer accepts nothing', (tester) async {
      final relay = ChatDropRelay();
      await _pump(tester, relay);
      await tester.pumpWidget(const SizedBox());
      expect(relay.accepts, isFalse);
    });
  });
}
