import 'package:flutter/material.dart';

import '../../../../common/back_chevron_button.dart';
import '../../mobile/mobile_shell_scope.dart';

/// The way back out of a page on a phone — to the list, or to the call a
/// conversation was opened over.
///
/// Draws nothing anywhere else: a desktop's panes sit side by side and there
/// is nothing to go back to. It pops the shell's navigator rather than closing
/// anything itself, so back from here and the system back gesture are one
/// path, and the shell decides what closing the page means.
class HeaderBackButton extends StatelessWidget {
  const HeaderBackButton({super.key});

  /// Whether there is anywhere to go back to. A spaced header row asks this
  /// and leaves the button out rather than laying out an empty one: the
  /// row's spacing goes round an empty box too, which set a desktop chat's
  /// title ten pixels further in than the call strip's.
  static bool shows(BuildContext context) =>
      MobileShellScope.maybeOf(context) != null &&
      Navigator.of(context).canPop();

  @override
  Widget build(BuildContext context) {
    if (!shows(context)) return const SizedBox.shrink();
    return BackChevronButton(onPressed: Navigator.of(context).maybePop);
  }
}
