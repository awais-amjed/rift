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

  /// Where a long form stops growing and starts scrolling. Without it a
  /// six-field form opens nearly as tall as the window, which is a lot of
  /// dialog for a form.
  final double maxHeight;

  const AppModal({
    super.key,
    required this.title,
    this.subtitle,
    this.titleIcon,
    required this.content,
    this.actions,
    this.maxWidth = 448,
    this.maxHeight = 560,
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
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxWidth,
              maxHeight: maxHeight,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppModalHeader(
                  title: title,
                  subtitle: subtitle,
                  titleIcon: titleIcon,
                ),
                Divider(height: 1, color: borderColor),
                // Content
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 18,
                    ),
                    child: content,
                  ),
                ),
                // Actions
                if (actions != null) ...[
                  Divider(height: 1, color: borderColor),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                    child: Row(
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
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
