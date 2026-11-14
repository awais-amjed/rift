import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rift/data/classes/server_user.dart';
import 'package:rift/data/classes/user_permissions.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/user_avatar.dart';
import 'package:rift/presentation/screens/home/profile/user_dock/widgets/dock_avatar_button.dart';

/// The dock's avatar darkens under the pointer through a colour filter, which
/// draws the avatar into a layer of its own every frame it is there. The dock
/// is on screen all the time, so the filter is there only while hovered, and
/// the avatar moves in and out of it without being built again.
void main() {
  testWidgets('no filter at rest, one while hovered, the same avatar', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [ThemeState()]),
        home: Scaffold(
          body: Center(
            child: DockAvatarButton(
              user: const ServerUser(
                id: 'u1',
                username: 'maya',
                displayName: 'Maya',
                permissions: UserPermissions(),
              ),
              onTap: () {},
            ),
          ),
        ),
      ),
    );
    final filter = find.byType(ColorFiltered);
    expect(filter, findsNothing);
    final avatar = tester.state(find.byType(UserAvatar));

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(DockAvatarButton)));
    await tester.pumpAndSettle();
    expect(filter, findsOneWidget);
    expect(tester.state(find.byType(UserAvatar)), same(avatar));

    await mouse.moveTo(Offset.zero);
    await tester.pumpAndSettle();
    expect(filter, findsNothing);
    expect(tester.state(find.byType(UserAvatar)), same(avatar));
  });
}
