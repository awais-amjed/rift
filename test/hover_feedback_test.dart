import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/enums/channel_type.dart';
import 'package:rift/logic/cubits/app/app_cubit.dart';
import 'package:rift/logic/cubits/channel_presence/channel_presence_cubit.dart';
import 'package:rift/logic/cubits/voice_listeners/voice_listeners_cubit.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/chat/composer/composer_icon_button.dart';
import 'package:rift/presentation/common/chat/composer/composer_send_button.dart';
import 'package:rift/data/classes/attachment.dart';
import 'package:rift/data/classes/channel.dart';
import 'package:rift/data/classes/server_user.dart';
import 'package:rift/data/classes/user_permissions.dart';
import 'package:rift/presentation/common/chat/attachments/attachment_file_card.dart';
import 'package:rift/presentation/common/popover_surface.dart';
import 'package:rift/presentation/common/tag_editor.dart';
import 'package:rift/presentation/screens/home/channels/channel_list/widgets/voice_channel_tile/voice_channel_tile.dart';
import 'package:rift/presentation/screens/home/profile/user_dock/widgets/dock_avatar_button.dart';

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

class _StubAppCubit extends Cubit<AppState> implements AppCubit {
  _StubAppCubit() : super(const AppState());

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubPresenceCubit extends Cubit<ChannelPresenceState>
    implements ChannelPresenceCubit {
  _StubPresenceCubit() : super(const ChannelPresenceState());

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// No bot can hear anything and none has been called in, which is the default
/// a real server starts at.
class _StubVoiceListenersCubit extends Cubit<VoiceBotsState>
    implements VoiceListenersCubit {
  _StubVoiceListenersCubit() : super(const VoiceBotsState());

  @override
  List<String> listening(String channelId) => const [];

  @override
  List<SummonedBot> summoned(String channelId) => const [];

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Whether hovering a control actually shows anything.
///
/// A control can be perfectly clickable and still look dead: an `InkWell`
/// paints its hover on the nearest `Material` *above* it, so one sitting
/// inside a box that paints its own background — the composer bar, a channel
/// card, an attachment card — has its highlight drawn and then covered. The
/// button works, nothing lights up, and the only way to find out where the tap
/// target is is to click and see.
///
/// Reasoning about that is how it got missed, so these render the pixels and
/// compare them. A control whose image is identical with the pointer on it and
/// off it is giving the user nothing, whatever the widget tree says.
void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    HydratedBloc.storage = _MemoryStorage();
  });

  /// The rendered pixels of [finder], which must be under a [RepaintBoundary].
  Future<Uint8List> pixels(WidgetTester tester, Finder finder) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.ancestor(of: finder, matching: find.byType(RepaintBoundary)).first,
    );
    late Uint8List bytes;
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      bytes = data!.buffer.asUint8List();
      image.dispose();
    });
    return bytes;
  }

  /// Pumps [child] on the opaque surface it really sits on — which is the
  /// whole point, since the bug is a highlight hiding *behind* that surface.
  Future<void> host(WidgetTester tester, Widget Function(ThemeState) child) {
    final theme = ThemeCubit().state;
    return tester.pumpWidget(
      BlocProvider<ThemeCubit>(
        create: (_) => ThemeCubit(),
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                child: ColoredBox(
                  color: theme.bgTertiary,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: child(theme),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Parks a mouse on [target] and returns the before/after pixels.
  Future<(Uint8List, Uint8List)> hover(
    WidgetTester tester,
    Finder target,
  ) async {
    final before = await pixels(tester, target);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(target));
    // A fixed run of frames rather than pumpAndSettle: some of these sit next
    // to something that animates forever — a live badge pulsing — and settling
    // is not what is being measured. Long enough for the fade to finish is.
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
    return (before, await pixels(tester, target));
  }

  testWidgets('a composer icon button lights up under the pointer', (
    tester,
  ) async {
    await host(
      tester,
      (theme) => ComposerIconButton(
        icon: Icons.sentiment_satisfied_alt_rounded,
        tooltip: 'Emoji',

        onPressed: () {},
      ),
    );

    final (idle, lit) = await hover(tester, find.byType(ComposerIconButton));
    expect(lit, isNot(idle));
  });

  testWidgets('a disabled composer icon button stays dark', (tester) async {
    // Feedback is a promise that a click will do something. One that has
    // nothing to do should not make it.
    await host(
      tester,
      (theme) => ComposerIconButton(
        icon: Icons.mic_none_rounded,
        tooltip: 'Record',

        onPressed: null,
      ),
    );

    final (idle, lit) = await hover(tester, find.byType(ComposerIconButton));
    expect(lit, idle);
  });

  testWidgets('the send button lights up under the pointer', (tester) async {
    // Its gradient is opaque, so an ink highlight behind it could never show
    // however many Materials it were given — it lifts itself instead.
    await host(
      tester,
      (theme) => ComposerSendButton(enabled: true, onPressed: () {}),
    );

    final (idle, lit) = await hover(tester, find.byType(ComposerSendButton));
    expect(lit, isNot(idle));
  });

  testWidgets('a send button with nothing to send stays dark', (tester) async {
    await host(
      tester,
      (theme) => ComposerSendButton(enabled: false, onPressed: () {}),
    );

    final (idle, lit) = await hover(tester, find.byType(ComposerSendButton));
    expect(lit, idle);
  });

  testWidgets('a row inside a popover lights up under the pointer', (
    tester,
  ) async {
    // [PopoverSurface] paints an opaque fill, so where it puts its Material
    // decides whether anything inside it can show a hover at all. This stands
    // in for the emoji picker's category icons and every other popover row
    // that isn't a `ContextMenuItem` — those carry a Material of their own and
    // were the only ones that ever worked.
    await host(
      tester,
      // Padded, so the row sits well inside the surface's rounded corners.
      // Flush against them the ink bleeds past the fill and the corners alone
      // would light up — which looks like a pass and proves nothing.
      (_) => PopoverSurface(
        padding: const EdgeInsets.all(8),
        child: InkWell(
          onTap: () {},
          borderRadius: BorderRadius.circular(6),
          child: const SizedBox(width: 120, height: 32),
        ),
      ),
    );

    final (idle, lit) = await hover(tester, find.byType(InkWell));
    expect(lit, isNot(idle));
  });

  testWidgets('an attachment card lights up under the pointer', (tester) async {
    // A control the size of a paragraph that gave no sign it was one: the
    // InkWell used to wrap the card, so its hover landed on the message row
    // behind and the card's own fill covered it.
    await host(
      tester,
      (theme) => AttachmentFileCard(
        attachment: const Attachment(
          id: 'a1',
          kind: AttachmentKind.file,
          name: 'notes.pdf',
          mime: 'application/pdf',
          size: 4096,
          storagePath: 's/a1.bin',
          keyB64: 'k',
          nonceB64: 'n',
        ),
        loader: (_) async => null,
      ),
    );

    final (idle, lit) = await hover(tester, find.byType(AttachmentFileCard));
    expect(lit, isNot(idle));
  });

  testWidgets('the way off a tag chip lights up under the pointer', (
    tester,
  ) async {
    await host(
      tester,
      (theme) => TagEditor(
        controller: TextEditingController(),
        tags: const ['board-games'],
        onChanged: (_) {},
      ),
    );

    final (idle, lit) = await hover(tester, find.byIcon(Icons.close_rounded));
    expect(lit, isNot(idle));
  });

  testWidgets('the dock avatar says what clicking it does', (tester) async {
    // The one control here that an ink surface cannot rescue — the avatar it
    // would sit behind is opaque — so it dims and shows a pencil instead. The
    // pencil staying invisible until hovered is half the assertion: an avatar
    // that always wore one would read as a broken image.
    await host(
      tester,
      (theme) => DockAvatarButton(
        user: ServerUser(
          id: 'u1',
          username: 'me',
          displayName: 'Me',
          permissions: UserPermissions(),
        ),

        onTap: () {},
      ),
    );

    double pencilOpacity() => tester
        .widget<AnimatedOpacity>(
          find.ancestor(
            of: find.byIcon(Icons.edit_rounded),
            matching: find.byType(AnimatedOpacity),
          ),
        )
        .opacity;

    expect(pencilOpacity(), 0);

    final (idle, lit) = await hover(tester, find.byType(DockAvatarButton));
    expect(lit, isNot(idle));
    expect(pencilOpacity(), 1);
  });

  /// Whether [inkWell] has anywhere visible to paint: walking up from it, a
  /// [Material] must turn up before anything that fills its own background
  /// does, or the highlight lands underneath that fill.
  bool inkCanBeSeen(WidgetTester tester, Finder inkWell) {
    var seen = false;
    tester.element(inkWell).visitAncestorElements((element) {
      final widget = element.widget;
      if (widget is Material) {
        seen = true;
        return false;
      }
      if (widget is Container && _paintsOver(widget)) return false;
      if (widget is ColoredBox && widget.color.a == 1) return false;
      return true;
    });
    return seen;
  }

  testWidgets('a voice channel header has somewhere to paint its hover', (
    tester,
  ) async {
    // The one row on the tile you can click, in a card that painted over its
    // highlight — so it looked exactly like the roster rows beneath it, which
    // you cannot click.
    //
    // Asserted structurally rather than by pixels: a selected tile carries a
    // LiveBadge that pulses forever, and an animation running between two
    // captures reads as a difference whatever the pointer is doing. The
    // invariant is the same one the pixel tests above are evidence for.
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<ThemeCubit>(create: (_) => ThemeCubit()),
          BlocProvider<AppCubit>(create: (_) => _StubAppCubit()),
          BlocProvider<VoiceListenersCubit>(
            create: (_) => _StubVoiceListenersCubit(),
          ),
          BlocProvider<ChannelPresenceCubit>(
            create: (_) => _StubPresenceCubit(),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 220,
                child: VoiceChannelTile(
                  channel: const Channel(
                    id: 'c1',
                    name: 'General',
                    channelType: ChannelType.voice,
                  ),
                  // Selected, because that is the branch that draws the card.
                  // An empty, unselected voice channel is a plain NavRow on
                  // the sidebar — no fill of its own, never part of this bug.
                  isSelected: true,
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(inkCanBeSeen(tester, find.byType(InkWell).first), isTrue);
  });
}

/// Whether [container] paints something the ink underneath it cannot show
/// through — a solid fill or any gradient.
bool _paintsOver(Container container) {
  if (container.color != null) return container.color!.a == 1;
  final decoration = container.decoration;
  if (decoration is! BoxDecoration) return false;
  return decoration.gradient != null || (decoration.color?.a ?? 0) == 1;
}
