import 'package:flutter/widgets.dart';

import '../../../../../../../responsive/shell_scope.dart';
import '../../../../../../../theme/app_text.dart';

/// How big a row in a voice channel's card is — the header and every person
/// under it — so the rows agree with each other.
///
/// A desktop's are a pointer's size, as the sidebar's rows are. A phone's list
/// is the whole screen and these rows are pressed with a thumb, so they grow
/// to roughly the height of a channel row beside them; at the desktop size the
/// card read as a squashed strip between full-height rows.
class RosterRowMetrics {
  final EdgeInsets padding;
  final double avatarSize;
  final double headerVerticalPadding;

  /// A person's name, before any colour or weight the row adds.
  final TextStyle nameStyle;

  /// Mic, deafen and mute marks at the end of a row.
  final double iconSize;

  const RosterRowMetrics._({
    required this.padding,
    required this.avatarSize,
    required this.headerVerticalPadding,
    required this.nameStyle,
    required this.iconSize,
  });

  static const _desktop = RosterRowMetrics._(
    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 5),
    avatarSize: 22,
    headerVerticalPadding: 5,
    nameStyle: AppText.secondary,
    iconSize: 11,
  );

  static const _phone = RosterRowMetrics._(
    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 9),
    avatarSize: 26,
    headerVerticalPadding: 9,
    nameStyle: AppText.rowQuiet,
    iconSize: 15,
  );

  static RosterRowMetrics of(BuildContext context) =>
      context.layoutMode.isCompact ? _phone : _desktop;
}
