import 'package:flutter/widgets.dart';

import '../../../../../../../../data/constants.dart';
import '../../../../../../../responsive/shell_scope.dart';
import '../../../../../../../theme/app_text.dart';

/// How big a row in a voice channel's card is — the header and every person
/// under it — so the rows agree with each other.
///
/// A desktop's are a pointer's size, as the sidebar's rows are. A phone's list
/// is the whole screen and these rows are pressed with a thumb, so they grow
/// to roughly the height of a channel row beside them; at the desktop size the
/// card read as a squashed strip between full-height rows.
///
/// **Every row is one height, and it is a sidebar row's.** The header used to
/// be three pixels shorter than the people under it, and taller than the plain
/// row an empty channel is drawn as, so joining a call moved the channel's
/// name. [rowHeight] is `NavRow`'s height at this size — its padding plus a
/// 20px line — and a person's padding is what puts their avatar in the middle
/// of it.
class RosterRowMetrics {
  /// Around a person: their avatar plus this is [rowHeight]. Across, it is
  /// [headerInset] less [cardInset], so avatars line up under the channel's
  /// glyph.
  final EdgeInsets padding;
  final double avatarSize;

  /// A `NavRow`'s height here: 7 + 20 + 7 at a desktop, 13 + 20 + 13 on a
  /// phone.
  final double rowHeight;

  /// Where a `NavRow` puts its icon, so the channel's glyph does not move
  /// sideways when the plain row becomes a card.
  static const double headerInset = 9;

  /// Between the card's border and the rows inside it. With the 1px border
  /// that is 4, which is [K.radiusCard] less [K.radiusRow]: a row's rounded
  /// highlight then runs parallel to the card's corner instead of being cut
  /// by it.
  static const double cardPadding = 3;

  /// The card's border plus [cardPadding], on every side. An empty voice
  /// channel keeps the same space above and below its plain row, so a call
  /// starting adds people under the name and moves nothing.
  static const double cardInset = cardPadding + 1;

  /// A person's name, before any colour or weight the row adds.
  final TextStyle nameStyle;

  /// Mic, deafen and mute marks at the end of a row.
  final double iconSize;

  const RosterRowMetrics._({
    required this.padding,
    required this.avatarSize,
    required this.rowHeight,
    required this.nameStyle,
    required this.iconSize,
  });

  static const _desktop = RosterRowMetrics._(
    padding: EdgeInsets.symmetric(horizontal: 5, vertical: 5),
    avatarSize: 24,
    rowHeight: 34,
    nameStyle: AppText.secondary,
    iconSize: 11,
  );

  static const _phone = RosterRowMetrics._(
    padding: EdgeInsets.symmetric(horizontal: 5, vertical: 10),
    avatarSize: 26,
    rowHeight: 46,
    nameStyle: AppText.rowQuiet,
    iconSize: 15,
  );

  static RosterRowMetrics of(BuildContext context) =>
      context.layoutMode.isCompact ? _phone : _desktop;
}
