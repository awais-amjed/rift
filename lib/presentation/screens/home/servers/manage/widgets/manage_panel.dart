import 'package:flutter/material.dart';

import '../../../../../common/button_footer.dart';
import '../../../../../common/hint_card.dart';
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

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    final readOnly = ManageReadOnly.of(context);
    final child = this.child;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppText.panelTitle.copyWith(
                  color: themeState.textPrimary,
                ),
              ),
              if (subtitle case final subtitle?) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppText.secondary.copyWith(
                    color: themeState.textTertiary,
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child:
              body ??
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 18),
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
        ),
        if (footer.isNotEmpty && !readOnly) ...[
          Divider(height: 1, color: themeState.borderPrimary),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 16),
            child: ButtonFooter(
              alignment: MainAxisAlignment.start,
              buttons: footer,
            ),
          ),
        ],
      ],
    );
  }
}

/// Marks the manage pages below it as view-only — a phone's server
/// management, where only Members stays editable.
///
/// The roles editor's permission grid, retention limits and listing details
/// are each one mistap from a change nobody meant, on a screen where the
/// reader can see a fraction of the page at once. Showing the current state
/// keeps them useful for checking; changing them waits for a bigger screen.
class ManageReadOnly extends InheritedWidget {
  const ManageReadOnly({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ManageReadOnly>() != null;

  @override
  bool updateShouldNotify(ManageReadOnly old) => false;
}
