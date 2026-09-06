import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/classes/chat_message.dart';
import 'package:rift/data/classes/role.dart';
import 'package:rift/data/enums/message_origin.dart';
import 'package:rift/data/enums/server_permission.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/chat/message_row/message_origin_badge.dart';
import 'package:rift/presentation/common/status_chip.dart';
import 'package:rift/presentation/screens/home/members_sidebar/widgets/role_chip.dart';
import 'package:rift/presentation/theme/app_theme.dart';
import 'package:rift/presentation/theme/custom_colors.dart';

import 'support/memory_storage.dart';

/// What the badges say, and what they must never claim.
///
/// Both are small chips carrying real consequences, and both explain
/// themselves the cheap way — a tooltip on the message badge, and nothing at
/// all on the role chip, because the word is the whole message.
void main() {
  setUpAll(() => HydratedBloc.storage = MemoryStorage());

  /// Pumps with the app's *real* ThemeData, not a bare MaterialApp — the
  /// tooltip's look and delay live in `tooltipTheme`, so a default theme here
  /// would be testing something the app never renders.
  Future<void> pump(WidgetTester tester, Widget child) {
    final themeCubit = ThemeCubit();
    return tester.pumpWidget(
      BlocProvider<ThemeCubit>.value(
        value: themeCubit,
        child: MaterialApp(
          theme: AppTheme.fromPalette(
            themeCubit.state.palette,
            Brightness.dark,
          ),
          home: Scaffold(body: Center(child: child)),
        ),
      ),
    );
  }

  ChatMessage hook() => ChatMessage(
    id: '1',
    authorId: '',
    authorName: 'GitHub',
    text: 'build passed',
    sentAt: DateTime.utc(2026, 1, 1),
    isMine: false,
    origin: MessageOrigin.webhook,
    isEncrypted: false,
  );

  group('the unencrypted badge', () {
    testWidgets('carries a tooltip saying the server can read it', (
      tester,
    ) async {
      await pump(
        tester,
        Builder(builder: (context) => MessageOriginBadge(message: hook())),
      );

      final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(tooltip.message, contains('the server can read it'));
      expect(tooltip.message, contains('not a member'));
    });

    testWidgets('and takes its look and delay from the app theme', (
      tester,
    ) async {
      // It was first reported as "there is no tooltip". Material's default is
      // a light pill with a 500ms wait — wrong colours for this app, and long
      // enough on a target this small to read as nothing being there.
      await pump(
        tester,
        Builder(builder: (context) => MessageOriginBadge(message: hook())),
      );

      final theme = Theme.of(tester.element(find.byType(MessageOriginBadge)));
      expect(
        theme.tooltipTheme.waitDuration!.inMilliseconds,
        lessThanOrEqualTo(200),
      );
      expect(theme.tooltipTheme.decoration, isNotNull);
      expect(theme.tooltipTheme.textStyle, isNotNull);
      // Flutter never wraps a tooltip, so a long one becomes a strip laid
      // across the window unless something caps it.
      expect(theme.tooltipTheme.constraints?.maxWidth, isNotNull);
      expect(theme.tooltipTheme.constraints!.maxWidth, lessThanOrEqualTo(360));

      // ...and the badge does not override either of them locally.
      final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(tooltip.waitDuration, isNull);
      expect(tooltip.decoration, isNull);
    });
  });

  group('the role chip', () {
    testWidgets('shows the role by name, cut to fit the row', (tester) async {
      // Names, not icons standing in for three fixed flags: a role is whatever
      // somebody made, so the chip has to be able to say anything — and a chip
      // that grew with it would push the name it annotates off the row.
      await pump(
        tester,
        Builder(
          builder: (context) => RoleChip(
            role: const Role(
              id: 'r',
              name: 'Moderator',
              position: 2,
              permissions: 0,
            ),
          ),
        ),
      );

      expect(find.text('MODERATOR'), findsNothing);
      expect(find.text('MODERAT\u2026'), findsOneWidget);
    });

    testWidgets('takes its colour from the role, when it was given one', (
      tester,
    ) async {
      await pump(
        tester,
        Builder(
          builder: (context) => RoleChip(
            role: const Role(
              id: 'r',
              name: 'Mods',
              position: 2,
              permissions: 0,
              color: '#22C55E',
            ),
          ),
        ),
      );

      final text = tester.widget<Text>(find.text('MODS'));
      expect(text.style?.color, const Color(0xFF22C55E));
    });

    testWidgets('leaves an uncoloured role alone', (tester) async {
      // Not being given a colour is a choice somebody made in the editor, so
      // inventing one for them would undo it.
      await pump(
        tester,
        Builder(
          builder: (context) => RoleChip(
            role: const Role(
              id: 'r',
              name: 'Mods',
              position: 2,
              permissions: 0,
            ),
          ),
        ),
      );

      final themeState = ThemeCubit().state;
      final text = tester.widget<Text>(find.text('MODS'));
      expect(text.style?.color, themeState.textTertiary);
    });
  });

  group('what a permission claims', () {
    test('manage-channels says where it stops', () {
      // It used to be one of three fixed roles whose description had to spell
      // out that a channel manager cannot ban. Now every permission is its own
      // bit, and the line that matters is the boundary the name does not
      // suggest: this one does not reach inside a private channel.
      final text = ServerPermission.manageChannels.description.toLowerCase();
      expect(text.contains('private'), isTrue);
    });

    test('kicking and banning are not the same grant', () {
      expect(
        ServerPermission.kickMembers.bit,
        isNot(ServerPermission.banMembers.bit),
      );
      final kick = ServerPermission.kickMembers.mask;
      expect(kick.has(ServerPermission.banMembers), isFalse);
    });
  });

  group('the Encrypted chip', () {
    testWidgets('explains what the claim covers', (tester) async {
      await pump(
        tester,
        const StatusChip(
          icon: Icons.lock_outline,
          label: 'Encrypted',
          color: CustomColors.success,
          tooltip: StatusChip.encryptedTooltip,
        ),
      );

      final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(tooltip.message, contains('Only the people in here can read'));
      expect(tooltip.message, contains('cannot read them'));
    });

    test('and never promises more than content', () {
      // Metadata is visible to the operator — who, when, where, how much
      // (ARCHITECTURE.md §6). A chip claiming the server sees "nothing" would
      // be the app overstating its own guarantee in its most prominent place.
      final text = StatusChip.encryptedTooltip.toLowerCase();
      expect(text.contains('nothing'), isFalse);
      expect(text.contains('anonymous'), isFalse);
      expect(text.contains('messages'), isTrue);
      // And it answers "who can read this", not "how does it work".
      expect(text.contains('can read'), isTrue);
    });

    testWidgets('a chip with nothing to add carries no tooltip', (
      tester,
    ) async {
      await pump(
        tester,
        const StatusChip(
          icon: Icons.tag_rounded,
          label: 'Central',
          color: CustomColors.success,
        ),
      );
      expect(find.byType(Tooltip), findsNothing);
    });
  });
}
