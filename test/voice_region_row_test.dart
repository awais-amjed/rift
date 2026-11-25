import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rift/data/classes/livekit_node.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/screens/home/servers/server_settings/voice/voice_region_row.dart';

import 'helpers/memory_storage.dart';

const _node = LiveKitNode(id: 'n', label: 'Singapore', url: 'wss://sg');

Future<void> _pump(WidgetTester tester, {required bool neverHeard}) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider(
            create: (_) => ThemeCubit(),
            child: VoiceRegionRow(
              node: _node,
              enabled: true,
              onEdit: () {},
              onRemove: () {},
              neverHeard: neverHeard,
            ),
          ),
        ),
      ),
    );

void main() {
  setUpAll(() => HydratedBloc.storage = MemoryStorage());

  // A region whose webhook never arrives still holds calls, so nothing else
  // shows it: joins there go unchecked (self-host `livekit_webhook`).
  testWidgets('a region never heard from says where to look', (tester) async {
    await _pump(tester, neverHeard: true);
    expect(find.textContaining('MAIN_SERVER'), findsOneWidget);
  });

  testWidgets('a region heard from says nothing more', (tester) async {
    await _pump(tester, neverHeard: false);
    expect(find.textContaining('MAIN_SERVER'), findsNothing);
    expect(find.text('Singapore'), findsOneWidget);
  });
}
