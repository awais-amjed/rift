import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/nav_row.dart';
import 'package:rift/presentation/screens/home/channels/channel_list/widgets/voice_channel_tile/widgets/voice_listening_badge.dart';

/// The marker that says a bot can hear a call.
///
/// It is the whole of BOTS.md §6's fourth rule in voice: the admin decides, and
/// everyone who speaks in the room pays for it, so the room has to say so
/// standing rather than in the dialog where the decision was made. A marker that
/// silently failed to draw would leave the grant working and the notice gone,
/// which is the one failure this design does not tolerate.
/// [ThemeCubit] is hydrated, and [NavRow] reads it.
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

void main() {
  setUpAll(() => HydratedBloc.storage = _MemoryStorage());

  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );

  testWidgets('no listener draws nothing at all', (tester) async {
    await tester.pumpWidget(wrap(const VoiceListeningBadge(listeners: [])));
    expect(find.byIcon(Icons.hearing_rounded), findsNothing);
    expect(find.textContaining('HEAR'), findsNothing);
  });

  testWidgets('one listener says the room is heard', (tester) async {
    await tester.pumpWidget(
      wrap(const VoiceListeningBadge(listeners: ['Scribe'])),
    );
    expect(find.text('HEARD'), findsOneWidget);
  });

  testWidgets('several are counted rather than listed', (tester) async {
    // A sidebar row already carries a channel name and a roster. The names are
    // one hover away.
    await tester.pumpWidget(
      wrap(const VoiceListeningBadge(listeners: ['Scribe', 'Notes'])),
    );
    expect(find.text('2 HEARING'), findsOneWidget);
  });

  testWidgets('hovering names them', (tester) async {
    await tester.pumpWidget(
      wrap(const VoiceListeningBadge(listeners: ['Scribe'])),
    );

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      pointer.hover(tester.getCenter(find.text('HEARD'))),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.textContaining('Scribe can hear this channel'), findsOneWidget);
  });

  testWidgets('and it still names them inside a NavRow', (tester) async {
    // The composition it actually ships in. A tooltip that works on its own and
    // not inside the row is a tooltip nobody ever sees — the sidebar wraps this
    // in an InkWell, and an InkWell brings a MouseRegion of its own.
    await tester.pumpWidget(
      wrap(
        BlocProvider(
          create: (_) => ThemeCubit(),
          child: const SizedBox(
            width: 300,
            child: NavRow(
              icon: Icons.volume_up_rounded,
              label: 'stage',
              trailing: VoiceListeningBadge(listeners: ['Scribe']),
            ),
          ),
        ),
      ),
    );

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      pointer.hover(tester.getCenter(find.text('HEARD'))),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.textContaining('Scribe can hear this channel'), findsOneWidget);
  });
}
