import 'package:flutter/material.dart';

import '../../../../../../data/classes/friend_buckets.dart';
import '../../../../../../data/constants.dart';
import '../../../../../theme/app_text.dart';
import '../../../../../theme/theme_context.dart';

/// Which list the friends page is showing.
enum FriendsTab {
  friends,
  pending,
  blocked;

  String get label => switch (this) {
    FriendsTab.friends => 'Friends',
    FriendsTab.pending => 'Pending',
    FriendsTab.blocked => 'Blocked',
  };

  /// The lists this tab draws, in the order it draws them. Pending is the
  /// only tab that shows two, each under its own heading.
  List<FriendBucket> get buckets => switch (this) {
    FriendsTab.friends => const [FriendBucket.friends],
    FriendsTab.pending => const [FriendBucket.incoming, FriendBucket.outgoing],
    FriendsTab.blocked => const [FriendBucket.blocked],
  };
}

/// The three-way switch at the top of the friends page.
///
/// A row of pills rather than Material's [TabBar]: there is no swiping between
/// these and no underline to animate, and the app's other segmented controls
/// are pills. The count rides *inside* the pill, so "Pending 2" is one thing
/// to read rather than a label with a badge parked beside it.
class FriendsTabBar extends StatelessWidget {
  final FriendsTab current;
  final ValueChanged<FriendsTab> onChanged;

  /// Tab → how many rows are behind it. A zero shows no number at all: an
  /// empty list is not news, and "Blocked 0" is a fact nobody asked for.
  final Map<FriendsTab, int> counts;

  const FriendsTabBar({
    super.key,
    required this.current,
    required this.onChanged,
    this.counts = const {},
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: 6,
      children: [
        for (final tab in FriendsTab.values)
          _TabPill(
            tab: tab,
            count: counts[tab] ?? 0,
            isSelected: tab == current,
            onTap: () => onChanged(tab),
          ),
      ],
    );
  }
}

/// Small enough to live here: it exists only to give one tab a shape, and is
/// meaningless outside the bar.
class _TabPill extends StatelessWidget {
  final FriendsTab tab;
  final int count;
  final bool isSelected;
  final VoidCallback onTap;

  const _TabPill({
    required this.tab,
    required this.count,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    final radius = BorderRadius.circular(K.radiusPill);

    return Material(
      color: isSelected ? themeState.bgTertiary : Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        borderRadius: radius,
        hoverColor: themeState.bgHover,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: isSelected ? themeState.borderPrimary : Colors.transparent,
            ),
          ),
          child: Text(
            count > 0 ? '${tab.label}  $count' : tab.label,
            style: AppText.row.copyWith(
              color: isSelected
                  ? themeState.textPrimary
                  : themeState.textTertiary,
            ),
          ),
        ),
      ),
    );
  }
}
