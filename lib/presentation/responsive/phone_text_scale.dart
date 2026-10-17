import 'package:flutter/widgets.dart';

import '../../data/enums/layout_mode.dart';

/// Sets the whole type scale a step larger on a phone.
///
/// [AppText] was drawn for a desktop read at arm's length, where 14px message
/// text and 13px rows are comfortable. A phone is held closer but its pixels
/// are smaller, and at those sizes a chat reads as fine print: both platforms'
/// own body text is 16–17. Rather than an eighth size per token, the seven
/// sizes keep their ratios and the scale moves together — body text lands on
/// 15, a row on just under 14.
///
/// Multiplies whatever the person has set in their system's text size rather
/// than replacing it, so someone who already asked for larger text gets this
/// on top, not instead.
class PhoneTextScale extends StatelessWidget {
  final Widget child;

  const PhoneTextScale({super.key, required this.child});

  /// Message text from 14 to 15.
  static const double factor = 15 / 14;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    if (!LayoutMode.forWidth(media.size.width).isCompact) return child;
    return MediaQuery(
      data: media.copyWith(textScaler: _Scaled(media.textScaler, factor)),
      child: child,
    );
  }
}

/// [base] with every size multiplied by [factor] before it is applied, which
/// keeps a non-linear system scaler non-linear.
class _Scaled extends TextScaler {
  final TextScaler base;
  final double factor;

  const _Scaled(this.base, this.factor);

  @override
  double scale(double fontSize) => base.scale(fontSize * factor);

  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => base.textScaleFactor * factor;

  @override
  bool operator ==(Object other) =>
      other is _Scaled && other.base == base && other.factor == factor;

  @override
  int get hashCode => Object.hash(base, factor);
}
