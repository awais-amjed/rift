import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/app_button.dart';
import 'package:rift/presentation/common/app_modal_header.dart';
import 'package:rift/presentation/common/context_menu/context_menu_item.dart';
import 'package:rift/presentation/common/hint_card.dart';
import 'package:rift/presentation/common/message_banner.dart';
import 'package:rift/presentation/common/nav_row.dart';
import 'package:rift/data/classes/role.dart';
import 'package:rift/presentation/screens/home/members_sidebar/widgets/role_chip.dart';
import 'package:rift/presentation/common/status_chip.dart';

/// In-memory stand-in so [ThemeCubit] (a HydratedCubit) can be built in tests.
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

/// Long enough that nothing fits, and one word so nothing can wrap its way out
/// of trouble either.
const _longLabel = 'Delete-this-channel-permanently-for-everyone';

/// Every shared widget that renders caller-supplied text, and how to build one.
/// Built lazily: [ThemeCubit] is hydrated, so it can't be constructed until
/// `setUpAll` has given it storage.
Map<String, Widget Function()> _cases() => {
  'AppButton': () => const AppButton(label: _longLabel, expanded: true),
  'AppButton with an icon': () => const AppButton(
    label: _longLabel,
    icon: Icon(Icons.add_rounded, size: 16),
    expanded: true,
  ),
  'NavRow': () => const NavRow(icon: Icons.tag_rounded, label: _longLabel),
  'NavRow with a trailing badge': () => const NavRow(
    icon: Icons.tag_rounded,
    label: _longLabel,
    trailing: Icon(Icons.circle, size: 10),
  ),
  'ContextMenuItem': () => ContextMenuItem(
    icon: Icons.delete_outline_rounded,
    label: _longLabel,
    onTap: () {},
  ),
  'ContextMenuItem with a trailing widget': () => ContextMenuItem(
    icon: Icons.badge_outlined,
    label: _longLabel,
    onTap: () {},
    trailing: const Icon(Icons.chevron_right_rounded, size: 16),
  ),
  'StatusChip': () => const StatusChip(
    icon: Icons.lock_rounded,
    label: _longLabel,
    color: Colors.green,
  ),
  'HintCard': () => const HintCard(icon: Icons.info_outline, text: _longLabel),
  'MessageBanner': () =>
      const MessageBanner(message: _longLabel, kind: MessageBannerKind.error),
  // A role's name is whatever somebody typed, so this chip is the one shared
  // widget whose content is entirely out of the app's hands.
  'RoleChip': () => RoleChip(
    role: const Role(id: 'r', name: _longLabel, position: 1, permissions: 0),
  ),
  'AppModalHeader': () =>
      const AppModalHeader(title: _longLabel, subtitle: _longLabel),
};

/// A shared widget doesn't get to choose how wide it is. It goes in a sidebar
/// that collapses, a dialog action row that divides its width evenly, a panel
/// the user can drag narrower — so a label laid out at its natural size is a
/// striped overflow bar waiting for a long enough string. Debug builds shout
/// about it; release builds just clip, which is worse.
///
/// Each one is squeezed to a width no real layout would ask for, and simply
/// must not throw. What it does with the space — ellipsis, wrap, clip — is its
/// own business; overflowing is not one of the options.
void main() {
  setUpAll(() => HydratedBloc.storage = _MemoryStorage());

  Future<void> pumpAt(WidgetTester tester, double width, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider(
            create: (_) => ThemeCubit(),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: width, child: child),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  // 120px is the bar because it is just under the narrowest width the app
  // actually hands one of these: a dialog's action row splits into ~113px
  // buttons, and the members sidebar is 232.
  //
  // The left sidebar *is* user-resizable, which is why K.sidebarMinWidth
  // exists — dragged to its floor it still leaves ~200px beside the rail, well
  // clear of this. `sidebar_sizing_test.dart` guards that relationship, so
  // lowering the floor there fails rather than quietly invalidating this.
  //
  // Deliberately not lower than 120. At 40px there is no room for one
  // character beside an icon, so the only way to pass would be to wrap
  // everything in a ClipRect — which hides content rather than fitting it, and
  // would be chasing a width no layout produces.
  const narrowest = 120.0;

  group('at ${narrowest.toInt()}px', () {
    _cases().forEach((name, build) {
      testWidgets(name, (tester) async {
        await pumpAt(tester, narrowest, build());
        expect(tester.takeException(), isNull);
      });
    });
  });
}
