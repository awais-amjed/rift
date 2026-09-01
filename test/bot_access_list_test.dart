import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/classes/channel.dart';
import 'package:rift/data/enums/channel_type.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/screens/home/channels/bots/widgets/bot_access_list.dart';

/// The two halves of "what does this thing see?".
///
/// Reading and hearing are separate grants with separate consequences — a
/// channel key cannot be taken back and a call can — so they are two lists, and
/// each has to be able to say *nothing*. The empty sentence is the one most
/// likely to surprise somebody arriving from Discord, where a bot in a call
/// hears everyone by default, so it is the part worth pinning down.
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

Channel _channel(String name, ChannelType type, {bool private = false}) =>
    Channel(id: name, name: name, channelType: type, isPrivate: private);

void main() {
  setUpAll(() => HydratedBloc.storage = _MemoryStorage());

  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: BlocProvider(create: (_) => ThemeCubit(), child: child),
      ),
    ),
  );

  Widget list({
    required String label,
    required List<Channel> channels,
    required String emptyText,
    Widget? control,
  }) => Builder(
    builder: (context) => BotAccessList(
      themeState: context.watch<ThemeCubit>().state,
      label: label,
      channels: channels,
      emptyIcon: Icons.volume_off_outlined,
      emptyText: emptyText,
      control: control,
    ),
  );

  testWidgets('a bot that hears nothing says so, and says why it does not '
      'matter for music', (tester) async {
    await pump(
      tester,
      list(
        label: 'Calls it can hear',
        channels: const [],
        emptyText:
            'It hears nothing. It can still speak in any call — '
            'playing music never needed permission.',
      ),
    );

    expect(find.text('Calls it can hear'), findsOneWidget);
    expect(find.textContaining('It hears nothing'), findsOneWidget);
    expect(find.textContaining('playing music never needed'), findsOneWidget);
  });

  testWidgets('channels it reaches are listed with their kind', (tester) async {
    await pump(
      tester,
      list(
        label: 'Calls it can hear',
        channels: [_channel('stage', ChannelType.voice)],
        emptyText: 'It hears nothing.',
      ),
    );

    expect(find.text('stage'), findsOneWidget);
    expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
    expect(find.textContaining('It hears nothing'), findsNothing);
  });

  testWidgets('a private one is marked, in either list', (tester) async {
    // Worth pointing out in both, and the sort of detail that gets added to one
    // list and forgotten in the other — which is why the row is shared.
    await pump(
      tester,
      list(
        label: 'Channels it can read',
        channels: [
          _channel('lobby', ChannelType.text),
          _channel('war-room', ChannelType.text, private: true),
        ],
        emptyText: 'It reads nothing.',
      ),
    );

    expect(find.byIcon(Icons.tag_rounded), findsNWidgets(2));
    expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
  });

  testWidgets('only the reading half carries a control', (tester) async {
    // There is no server-wide form for hearing, by design (BOTS.md §6b), so
    // this slot stays empty on the voice list rather than being disabled.
    await pump(
      tester,
      list(
        label: 'Channels it can read',
        channels: const [],
        emptyText: 'It reads nothing.',
        control: const Text('every public channel'),
      ),
    );
    expect(find.text('every public channel'), findsOneWidget);

    await pump(
      tester,
      list(
        label: 'Calls it can hear',
        channels: const [],
        emptyText: 'It hears nothing.',
      ),
    );
    expect(find.text('every public channel'), findsNothing);
  });
}
