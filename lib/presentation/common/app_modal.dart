import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/constants.dart';
import '../../logic/cubits/theme/theme_cubit.dart';
import 'app_modal_header.dart';

/// Shows a dialog that:
/// - Cannot be dismissed by tapping the barrier
/// - CAN be dismissed by pressing Escape
Future<T?> showCustomDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => CallbackShortcuts(
      bindings: {
        SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(ctx).pop(),
      },
      child: Focus(autofocus: true, child: builder(ctx)),
    ),
  );
}

/// Helper to show an AppModal as a dialog.
Future<T?> showAppModal<T>({
  required BuildContext context,
  required Widget modal,
}) {
  return showCustomDialog<T>(context: context, builder: (_) => modal);
}

/// Base modal used for most dialogs in the app.
class AppModal extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? titleIcon;
  final Widget content;
  final List<Widget>? actions;
  final double maxWidth;

  /// Fill the window rather than hugging the content, leaving [K.dialogInset]
  /// of the app showing around the edge. For the long setup forms — creating a
  /// server, joining one — where a box sized to its content spends the whole
  /// flow scrolling inside a window that has room to spare.
  ///
  /// The frame grows; the column inside it stays [maxWidth] and centres.
  final bool fullPage;

  const AppModal({
    super.key,
    required this.title,
    this.subtitle,
    this.titleIcon,
    required this.content,
    this.actions,
    this.maxWidth = 448,
    this.fullPage = false,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        final borderColor = themeState.borderPrimary;

        return Dialog(
          // The design puts dialogs on the *panel* surface, with the shadow
          // doing the lifting — elevated is reserved for menus and popovers,
          // which open on top of dialogs and need to out-rank them.
          backgroundColor: themeState.bgSecondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(K.radiusDialog),
            side: BorderSide(color: themeState.borderElevated),
          ),
          insetPadding: fullPage
              ? const EdgeInsets.all(K.dialogInset)
              : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
          child: ConstrainedBox(
            constraints: fullPage
                ? const BoxConstraints.expand()
                : BoxConstraints(maxWidth: maxWidth),
            child: Column(
              mainAxisSize: fullPage ? MainAxisSize.max : MainAxisSize.min,
              children: [
                // Header — full width even on a full-page modal, so the title
                // sits in the corner of the frame and the close button stays
                // where a close button belongs.
                AppModalHeader(
                  title: title,
                  subtitle: subtitle,
                  titleIcon: titleIcon,
                  large: fullPage,
                ),
                Divider(height: 1, color: borderColor),
                Flexible(child: _body()),
                // Actions
                if (actions != null) ...[
                  Divider(height: 1, color: borderColor),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                    child: _column(
                      Row(
                        children: actions!
                            .map((a) => Expanded(child: a))
                            .toList()
                            .fold<List<Widget>>([], (acc, widget) {
                              if (acc.isNotEmpty) {
                                acc.add(const SizedBox(width: 10));
                              }
                              acc.add(widget);
                              return acc;
                            }),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  /// The scrolling middle of the modal.
  ///
  /// Full-page, the form is also centred *vertically*: a three-field form
  /// pinned to the top of a window-tall frame reads as an accident. The
  /// minimum height is what does it — the form sits in the middle while it
  /// fits and scrolls from the top once it doesn't.
  Widget _body() {
    const padding = EdgeInsets.symmetric(horizontal: 20, vertical: 18);

    if (!fullPage) {
      return SingleChildScrollView(padding: padding, child: content);
    }

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: padding,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: constraints.maxHeight - padding.vertical,
          ),
          child: Center(child: _column(content)),
        ),
      ),
    );
  }

  /// The readable column a full-page modal's form lives in: the frame grows
  /// with the window, the fields and their buttons stay [maxWidth] and centred
  /// under the header. Content-sized modals are already that narrow, so they
  /// pass straight through.
  Widget _column(Widget child) => fullPage
      ? Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: child,
          ),
        )
      : child;
}
