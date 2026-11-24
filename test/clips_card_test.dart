import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rift/data/classes/call_clip_audio.dart';
import 'package:rift/data/classes/stored_clip.dart';
import 'package:rift/data/enums/auth_status.dart';
import 'package:rift/logic/cubits/app/app_cubit.dart';
import 'package:rift/logic/cubits/clip_history/clip_history_cubit.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/logic/cubits/vault/vault_cubit.dart';
import 'package:rift/logic/services/call_clip/clip_library.dart';
import 'package:rift/presentation/common/context_menu/context_menu_watcher.dart';
import 'package:rift/presentation/screens/home/call_clip/clips_card.dart';
import 'package:rift/presentation/screens/home/controls/widgets/clips_button.dart';
import 'package:rift_crypto/rift_crypto.dart';

import 'support/memory_storage.dart';

final _seed = CryptoRepository.toBase64(Uint8List.fromList(List.filled(32, 7)));

class _UnlockedVault extends VaultCubit {
  _UnlockedVault() {
    emit(VaultState(status: AuthStatus.unlocked, masterSeed: _seed));
  }
}

/// The Clips card in a call: a way to clip without the shortcut, and the
/// clips this device keeps, each to open again or delete.
void main() {
  late Directory root;
  late ClipLibrary library;

  setUp(() {
    HydratedBloc.storage = MemoryStorage();
    root = Directory.systemTemp.createTempSync('rift_clips_card_test');
    library = ClipLibrary(root: () async => root);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<void> keep(WidgetTester tester, int second, String place) =>
      tester.runAsync(
        () => library.add(
          _seed,
          CallClipAudio(
            id: second,
            pcm: Int16List(96000 * 2),
            rate: 48000,
            channels: 2,
            at: DateTime.now().toUtc().subtract(Duration(minutes: second)),
          ),
          serverId: 's1',
          channelId: 'c1',
          place: place,
          fromDmCall: false,
        ),
      );

  /// Lets the disk and the cipher answer, then draws what they said.
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
  }

  Future<({AppCubit app, List<String> did})> pump(WidgetTester tester) async {
    final app = AppCubit();
    final history = ClipHistoryCubit(library: library);
    addTearDown(history.close);
    final did = <String>[];
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<ThemeCubit>(create: (_) => ThemeCubit()),
          BlocProvider<AppCubit>.value(value: app),
          BlocProvider<VaultCubit>(create: (_) => _UnlockedVault()),
          BlocProvider<ClipHistoryCubit>.value(value: history),
        ],
        child: MaterialApp(home: Scaffold(body: Container())),
      ),
    );
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          body: Center(
            child: SizedBox(
              width: ClipsCard.width,
              height: 500,
              child: ClipsCard(
                onClip: () => did.add('clip'),
                onOpen: (StoredClip clip) => did.add('open ${clip.place}'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await settle(tester);
    return (app: app, did: did);
  }

  testWidgets('with clipping off, it offers the switch and says who knows', (
    tester,
  ) async {
    final (:app, :did) = await pump(tester);
    expect(find.text('Clipping is off.'), findsOneWidget);
    expect(
      find.text('People in the call see that you have clipping on.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Turn on clipping'));
    await tester.pumpAndSettle();
    expect(app.state.clippingEnabled, isTrue);
    expect(find.text('Clip the last minute'), findsOneWidget);
    expect(did, isEmpty);
  });

  testWidgets('Clip closes the card and clips', (tester) async {
    final (:app, :did) = await pump(tester);
    app.setClippingEnabled(true);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clip the last minute'));
    await tester.pumpAndSettle();
    expect(did, ['clip']);
    expect(find.byType(ClipsCard), findsNothing);
  });

  testWidgets('lists the kept clips, newest first, and opens one', (
    tester,
  ) async {
    await keep(tester, 5, 'General · Rift Test');
    await keep(tester, 1, 'Fuck San · Garcie’s Server');
    final (app: _, :did) = await pump(tester);
    expect(find.textContaining('· 0:02'), findsNWidgets(2));
    expect(
      tester.getTopLeft(find.text('Fuck San · Garcie’s Server')).dy,
      lessThan(tester.getTopLeft(find.text('General · Rift Test')).dy),
    );
    await tester.tap(find.text('General · Rift Test'));
    await tester.pumpAndSettle();
    expect(did, ['open General · Rift Test']);
    expect(find.byType(ClipsCard), findsNothing);
  });

  testWidgets('deletes one, then all after asking', (tester) async {
    await keep(tester, 2, 'One');
    await keep(tester, 1, 'Two');
    await pump(tester);
    await tester.tap(find.byTooltip('Delete clip').first);
    await settle(tester);
    expect(find.text('Two'), findsNothing);
    expect(find.text('One'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete all clips'));
    await tester.pumpAndSettle();
    expect(find.text('Delete all clips?'), findsOneWidget);
    await tester.tap(find.text('Delete all').last);
    await settle(tester);
    expect(find.text('One'), findsNothing);
    expect(find.text('No clips yet.'), findsOneWidget);
  });

  testWidgets('the open card keeps the call\'s controls up', (tester) async {
    // A panel is a route over the stage: the pointer on it reads as the
    // pointer gone idle, and the bar it hangs from faded out from under it.
    var opened = 0;
    var closed = 0;
    final history = ClipHistoryCubit(library: library);
    addTearDown(history.close);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<ThemeCubit>(create: (_) => ThemeCubit()),
          BlocProvider<AppCubit>(create: (_) => AppCubit()),
          BlocProvider<VaultCubit>(create: (_) => _UnlockedVault()),
          BlocProvider<ClipHistoryCubit>.value(value: history),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ContextMenuWatcher(
              onOpened: () => opened++,
              onClosed: () => closed++,
              child: const Align(
                alignment: Alignment.bottomCenter,
                child: ClipsButton(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(ClipsButton));
    await tester.pumpAndSettle();
    expect(find.byType(ClipsCard), findsOneWidget);
    expect((opened, closed), (1, 0));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(ClipsCard), findsNothing);
    expect((opened, closed), (1, 1));
  });
}
