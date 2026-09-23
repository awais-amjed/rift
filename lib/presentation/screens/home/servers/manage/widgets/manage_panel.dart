import 'package:flutter/material.dart';

import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../common/button_footer.dart';
import '../../../../../common/hint_card.dart';
import '../../../../../common/more_below_fade.dart';
import '../../../../../common/scrolled_under_rule.dart';
import '../../../../../theme/app_text.dart';
import '../../../../../theme/theme_context.dart';

/// One page of the manage-server dialog: a heading, the page, and its own
/// footer.
///
/// Each page owns its buttons rather than the dialog owning one footer for
/// all of them, because the pages do different things — one saves a form,
/// one mints a link, one only lists — and a shared footer would be a row of
/// buttons that mean something on one page and nothing on the next. The
/// footer sits on the left, as it does in settings.
///
/// Under a [ManageReadOnly], the page is shown but can't be changed: a note
/// says so, the page's controls take no input, and its footer isn't drawn.
class ManagePanel extends StatelessWidget {
  final String title;
  final String? subtitle;

  /// A page that scrolls as a whole. Exactly one of this and [body].
  final Widget? child;

  /// A page that owns its own scrolling — a list that pages as it goes.
  final Widget? body;

  final List<Widget> footer;

  const ManagePanel({
    super.key,
    required this.title,
    this.subtitle,
    this.child,
    this.body,
    this.footer = const [],
  }) : assert((child == null) != (body == null));

  /// The page's own title, which travels with whichever half needs it.
  ///
  /// A page that scrolls as a whole scrolls this too — it is the top of the
  /// page, not furniture bolted above it, and the dialog's own header already
  /// says which dialog this is. A page that is a *list* keeps it, because
  /// there the title sits with a search field over rows that page as they
  /// go, and scrolling that away would take the search with it.
  Widget _heading(ThemeState themeState, {required bool scrollsAway}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 18, 24, scrollsAway ? 14 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppText.panelTitle.copyWith(color: themeState.textPrimary),
          ),
          if (subtitle case final subtitle?) ...[
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: AppText.secondary.copyWith(color: themeState.textTertiary),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    final readOnly = ManageReadOnly.of(context);
    final headingAbove = ManageHeadingAbove.of(context);
    final child = this.child;
    final body = this.body;

    // A list that pages as it goes cannot carry its own title away, so there
    // the heading stays put and the rows pass under a rule. Everywhere else
    // the page scrolls whole and needs neither.
    if (body != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!headingAbove) _heading(themeState, scrollsAway: false),
          Expanded(
            child: ScrolledUnderRule(
              child: MoreBelowFade(color: themeState.bgSecondary, child: body),
            ),
          ),
          if (footer.isNotEmpty && !readOnly) ..._footer(themeState),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          // Faded at the foot, or the page is sliced against the footer
          // wherever the cut falls — a field label cut through the middle of
          // its letters, with a hairline under it that reads as the end of
          // the panel rather than the middle of it.
          child: MoreBelowFade(
            color: themeState.bgSecondary,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!headingAbove) _heading(themeState, scrollsAway: true),
                  Padding(
                    // The heading supplied the top gap; without it the content
                    // would start flush against the header above.
                    padding: EdgeInsets.fromLTRB(
                      24,
                      headingAbove ? 14 : 0,
                      24,
                      18,
                    ),
                    child: readOnly
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            spacing: 16,
                            children: [
                              const HintCard(
                                icon: Icons.visibility_outlined,
                                text:
                                    'View only on a phone. This page is easy to '
                                    'get wrong on a small screen, so changing it '
                                    'needs Rift on a computer.',
                              ),
                              // Inside the scroll view, so the page still scrolls
                              // while nothing on it can be pressed.
                              AbsorbPointer(child: ExcludeFocus(child: child!)),
                            ],
                          )
                        : child,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (footer.isNotEmpty && !readOnly) ..._footer(themeState),
      ],
    );
  }

  /// The page's own buttons, on a rule. Both shapes end the same way.
  List<Widget> _footer(ThemeState themeState) => [
    Divider(height: 1, color: themeState.borderPrimary),
    Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 16),
      child: ButtonFooter(alignment: MainAxisAlignment.start, buttons: footer),
    ),
  ];
}

/// Marks the manage pages below it as view-only — a phone's server
/// management, where only Members stays editable.
///
/// The roles editor's permission grid, retention limits and listing details
/// are each one mistap from a change nobody meant, on a screen where the
/// reader can see a fraction of the page at once. Showing the current state
/// keeps them useful for checking; changing them waits for a bigger screen.
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

class ManageReadOnly extends InheritedWidget {
  const ManageReadOnly({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ManageReadOnly>() != null;

  @override
  bool updateShouldNotify(ManageReadOnly old) => false;
}
