import 'package:flutter/widgets.dart';

/// Set where the page's name is already drawn above the panel.
///
/// On a phone the modal is a page and its header carries the name of the page
/// you are on, so a [ManagePanel] that drew its own heading as well gave the
/// screen two headlines and four lines of titling before any content. On a
/// desktop the two sit in different regions — a header bar above a rule, then
/// the nav beside the page — and read as chrome and content, so there the
/// panel keeps its own.
class ManageHeadingAbove extends InheritedWidget {
  const ManageHeadingAbove({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ManageHeadingAbove>() != null;

  @override
  bool updateShouldNotify(ManageHeadingAbove old) => false;
}
