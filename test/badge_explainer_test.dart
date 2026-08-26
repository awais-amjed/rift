import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/classes/chat_message.dart';
import 'package:rift/data/classes/user_permissions.dart';
import 'package:rift/data/enums/message_origin.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/server_role.dart';
import 'package:rift/presentation/common/chat/message_row/message_origin_badge.dart';
import 'package:rift/presentation/screens/home/members_sidebar/widgets/role_chip.dart';

import 'support/memory_storage.dart';

/// A badge that carries a consequence has to be able to explain itself.
///
/// Both of these are opaque three-to-seven letter chips that are obvious to
/// whoever added them and meaningless to everybody else, and a tooltip only
/// half-answers it — it needs a mouse, so a phone never sees one.
void main() {
  setUpAll(() => HydratedBloc.storage = MemoryStorage());

  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    BlocProvider<ThemeCubit>(
      create: (_) => ThemeCubit(),
      child: MaterialApp(
        home: Scaffold(body: Center(child: child)),
      ),
    ),
  );

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
    testWidgets('tapping it explains what unencrypted means', (tester) async {
      await pump(
        tester,
        Builder(
          builder: (context) => MessageOriginBadge(
            message: hook(),
            themeState: context.read<ThemeCubit>().state,
          ),
        ),
      );

      await tester.tap(find.byType(MessageOriginBadge));
      await tester.pumpAndSettle();

      expect(find.text('Posted by an integration'), findsOneWidget);
      expect(find.textContaining('the server can read it'), findsOneWidget);
    });

    testWidgets('and says the rest of the channel is still safe', (
      tester,
    ) async {
      // A warning that overstates itself is one people learn to skip. This one
      // must not imply the whole channel is readable.
      await pump(
        tester,
        Builder(
          builder: (context) => MessageOriginBadge(
            message: hook(),
            themeState: context.read<ThemeCubit>().state,
          ),
        ),
      );

      await tester.tap(find.byType(MessageOriginBadge));
      await tester.pumpAndSettle();

      expect(find.textContaining('still end-to-end encrypted'), findsOneWidget);
    });
  });

  group('the role chip', () {
    testWidgets('a channel manager is not called MOD', (tester) async {
      // It implied ban and mute, which `moderate_user` reserves for admins,
      // and it was a third name for a role two other surfaces already call
      // "Channel Manager".
      await pump(
        tester,
        Builder(
          builder: (context) => RoleChip(
            role: ServerRole.channelManager,
            themeState: context.read<ThemeCubit>().state,
          ),
        ),
      );

      expect(find.text('MOD'), findsNothing);
      expect(find.text('MANAGER'), findsOneWidget);
    });

    testWidgets('tapping it lists what the role actually grants', (
      tester,
    ) async {
      await pump(
        tester,
        Builder(
          builder: (context) => RoleChip(
            role: ServerRole.channelManager,
            themeState: context.read<ThemeCubit>().state,
          ),
        ),
      );

      await tester.tap(find.byType(RoleChip));
      await tester.pumpAndSettle();

      expect(find.text('Channel Manager'), findsOneWidget);
      expect(find.textContaining('delete channels'), findsOneWidget);
    });
  });

  group('what the description claims', () {
    test('a channel manager is never described as moderating members', () {
      // Muting, deafening and banning all go through `moderate_user`, which
      // checks `app.is_admin()`. Claiming otherwise in the permissions dialog
      // would have an admin hand out a power believing it were smaller.
      final text = ServerRole.channelManager.description.toLowerCase();
      expect(text.contains('moderate members'), isFalse);
      expect(text.contains('ban'), isFalse);
      expect(text.contains('mute'), isFalse);
    });

    test('and the role it describes is the one it checks', () {
      const manager = UserPermissions(
        isServerAdmin: false,
        isChannelManager: true,
        canCreateTokens: false,
      );
      expect(ServerRole.channelManager.isHeldBy(manager), isTrue);
      expect(ServerRole.admin.isHeldBy(manager), isFalse);
    });
  });
}
