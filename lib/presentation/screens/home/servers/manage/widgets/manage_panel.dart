import 'package:flutter/material.dart';

import '../../../../../common/button_footer.dart';
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
                child: child,
              ),
        ),
        if (footer.isNotEmpty) ...[
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
