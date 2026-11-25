import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rift/logic/cubits/app/app_cubit.dart';
import 'package:rift/logic/cubits/livekit/livekit_cubit.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/logic/cubits/vault/vault_cubit.dart';
import 'package:rift/logic/services/connection_failure.dart';
import 'package:rift/presentation/screens/home/participants_grid/widgets/error_view.dart';

/// In-memory stand-in for the HydratedCubits under test.
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

const _channelId = 'vc-1';

/// Built with no session, so every join fails at the first check. That is
/// enough to exercise the retry path itself without a live room.
LiveKitCubit _buildCubit() =>
    LiveKitCubit(appCubit: AppCubit(), vaultCubit: VaultCubit());

Future<void> _pumpErrorView(
  WidgetTester tester, {
  VoidCallback? onRetry,
  VoidCallback? onLeave,
  String leaveLabel = 'Leave channel',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: BlocProvider(
          create: (_) => ThemeCubit(),
          child: ErrorView(
            failure: const ConnectionFailure(
              title: 'Cannot reach this server',
              message: 'Nothing answered.',
              detail: 'SocketException: connection refused',
            ),
            onRetry: onRetry,
            onLeave: onLeave,
            leaveLabel: leaveLabel,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUp(() => HydratedBloc.storage = _MemoryStorage());

  group('retryConnection', () {
    test('attempts the channel that failed again', () async {
      final cubit = _buildCubit();
      await cubit.connectToChannel(channelId: _channelId, serverId: 'srv-1');
      expect(cubit.state.connectionState, LiveKitConnectionState.error);

      final seen = <LiveKitConnectionState>[];
      final sub = cubit.stream.listen((s) => seen.add(s.connectionState));
      await cubit.retryConnection();
      await sub.cancel();

      // A real second attempt, not a no-op: it passes back through connecting.
      expect(seen, contains(LiveKitConnectionState.connecting));
      expect(cubit.state.currentChannelId, _channelId);
      await cubit.close();
    });

    test('does nothing when no channel was ever attempted', () async {
      final cubit = _buildCubit();

      final seen = <LiveKitState>[];
      final sub = cubit.stream.listen(seen.add);
      await cubit.retryConnection();
      await sub.cancel();

      expect(seen, isEmpty);
      await cubit.close();
    });
  });

  group('ErrorView actions', () {
    testWidgets('offers both ways out when the connection failed', (
      tester,
    ) async {
      await _pumpErrorView(tester, onRetry: () {}, onLeave: () {});

      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Leave channel'), findsOneWidget);
    });

    testWidgets('a DM call that could not connect is hung up, not left', (
      tester,
    ) async {
      // Found live, Nov 23: a DM call's failure offered "Leave channel".
      await _pumpErrorView(
        tester,
        onRetry: () {},
        onLeave: () {},
        leaveLabel: 'Hang up',
      );

      expect(find.text('Hang up'), findsOneWidget);
      expect(find.text('Leave channel'), findsNothing);
    });

    testWidgets('shows no actions for a precondition failure', (tester) async {
      // How the screen renders "no account" / "no LiveKit URL": a retry there
      // would only reprint the same message.
      await _pumpErrorView(tester);

      expect(find.text('Try again'), findsNothing);
      expect(find.text('Leave channel'), findsNothing);
    });

    testWidgets('the buttons fire their callbacks', (tester) async {
      var retried = 0;
      var left = 0;
      await _pumpErrorView(
        tester,
        onRetry: () => retried++,
        onLeave: () => left++,
      );

      await tester.tap(find.text('Try again'));
      await tester.tap(find.text('Leave channel'));
      await tester.pump();

      expect(retried, 1);
      expect(left, 1);
    });
  });
}
