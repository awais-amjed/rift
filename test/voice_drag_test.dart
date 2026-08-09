import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/classes/voice_drag.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/screens/home/channels/channel_list/widgets/voice_channel_tile/widgets/channel_drop_target.dart';
import 'package:rift/presentation/screens/home/sidebar/widgets/draggable_member.dart';

/// In-memory stand-in so the hydrated theme cubit can be built in tests.
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

const _member = VoiceDrag(
  userId: 'u1',
  name: 'Ada',
  fromChannelId: 'lounge',
  isLocal: false,
);

/// A row above a channel, laid out far enough apart to drag between them.
Widget _harness({
  required bool enabled,
  required String channelId,
  void Function(VoiceDrag)? onDropped,
}) {
  return MaterialApp(
    home: BlocProvider(
      create: (_) => ThemeCubit(),
      child: Scaffold(
        body: Column(
          children: [
            DraggableMember(
              enabled: enabled,
              member: _member,
              child: const SizedBox(
                height: 40,
                width: 200,
                child: ColoredBox(color: Color(0xFF222222)),
              ),
            ),
            const SizedBox(height: 200),
            if (onDropped == null)
              ChannelDropTarget(
                channelId: channelId,
                builder: (context, isTargeted) => SizedBox(
                  height: 40,
                  width: 200,
                  child: ColoredBox(
                    color: isTargeted
                        ? const Color(0xFF00FF00)
                        : const Color(0xFF333333),
                  ),
                ),
              )
            else
              DragTarget<VoiceDrag>(
                onAcceptWithDetails: (details) => onDropped(details.data),
                builder: (context, _, _) => const SizedBox(
                  height: 40,
                  width: 200,
                  child: ColoredBox(color: Color(0xFF333333)),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// The drop area — always the last box in the column.
Finder get _target => find.byType(ColoredBox).last;

void main() {
  setUp(() => HydratedBloc.storage = _MemoryStorage());

  group('dragging a member', () {
    testWidgets('carries who they are and where they came from', (
      tester,
    ) async {
      VoiceDrag? dropped;
      await tester.pumpWidget(
        _harness(
          enabled: true,
          channelId: 'gaming',
          onDropped: (member) => dropped = member,
        ),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(DraggableMember)),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(kLongPressTimeout);
      await gesture.moveTo(tester.getCenter(_target));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(dropped?.userId, 'u1');
      expect(dropped?.fromChannelId, 'lounge');
    });

    testWidgets('does not lift at all when we are not allowed to move them', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(enabled: false, channelId: 'gaming'));

      // No Draggable in the tree is the point: a row that can't go anywhere
      // must not follow the pointer and then snap back.
      expect(find.byType(Draggable<VoiceDrag>), findsNothing);
    });
  });

  group('a channel drop target', () {
    testWidgets('lights up for a member arriving from elsewhere', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(enabled: true, channelId: 'gaming'));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(DraggableMember)),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(kLongPressTimeout);
      await gesture.moveTo(tester.getCenter(_target));
      await tester.pump();

      expect(
        (tester.widget<ColoredBox>(_target)).color,
        const Color(0xFF00FF00),
      );

      // Cancelled rather than dropped: this test is about the highlight, and
      // completing the drop would send the move.
      await gesture.cancel();
      await tester.pumpAndSettle();
    });

    testWidgets('stays cold for the channel they are already in', (
      tester,
    ) async {
      // Rejected before it starts, so the tile never promises a move that
      // would do nothing — and the drop never reaches the server.
      await tester.pumpWidget(_harness(enabled: true, channelId: 'lounge'));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(DraggableMember)),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(kLongPressTimeout);
      await gesture.moveTo(tester.getCenter(_target));
      await tester.pump();

      expect(
        (tester.widget<ColoredBox>(_target)).color,
        const Color(0xFF333333),
      );

      await gesture.cancel();
      await tester.pumpAndSettle();
    });
  });
}
