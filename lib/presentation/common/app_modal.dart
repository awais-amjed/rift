import 'package:flutter/material.dart';

import '../../data/constants.dart';
import '../responsive/shell_scope.dart';
import '../theme/app_text.dart';
import '../theme/theme_context.dart';
import 'app_button_height.dart';
import 'app_modal_header.dart';
import 'back_chevron_button.dart';
import 'button_footer.dart';
import 'message_banner.dart';

export 'show_custom_dialog.dart';

part 'app_modal_phone.dart';

/// Base modal used for every dialog in the app.
///
/// A dialog is either a form, which goes in [content] and scrolls as a whole
/// when the window is short, or a list, which goes in [body] and scrolls
/// itself. The shell — surface, radius, header, footer — is the same either
/// way, which is the point: a dialog that hand-rolls its chrome because its
/// body scrolls is a second dialog design.
class AppModal extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? titleIcon;

  /// A figure beside the title. See [AppModalHeader.count].
  final int? count;

  /// Icon buttons in the header, before the close button.
  final List<Widget> headerActions;

  /// A form: padded, and scrolled as a whole when there is not room for it.
  /// Exactly one of [content] and [body] is given.
  final Widget? content;

  /// Why the last attempt failed, shown above [content] until it is cleared.
  ///
  /// Every form dialog had the same banner and the same gap hand-placed at the
  /// top of its column; this is that, once.
  final String? error;

  /// A body that owns its own scrolling — a `ListView` with a search row
  /// above it, say. Given the remaining height and no padding; what is inside
  /// decides both.
  final Widget? body;

  final List<Widget>? actions;
  final double maxWidth;

  /// Where a long form stops growing and starts scrolling.
  ///
  /// Defaults to [_maxHeightFraction] of the window rather than a fixed number
  /// of pixels: the point of the cap is to leave the app visible around the
  /// dialog, and how much room there is to leave is a property of the window,
  /// not of the form. A fixed cap made the create-server form scroll on a
  /// screen with several hundred pixels to spare.
  final double? maxHeight;

  /// How much of the window a modal may fill before it starts scrolling.
  static const _maxHeightFraction = 0.85;

  /// The same, for a sheet — a little more, because what is above a sheet is
  /// the screen it came from and is worth keeping a strip of.
  static const _sheetMaxFraction = 0.88;

  /// Keeps the centred dialog on a phone, where every other modal fills the
  /// screen. For a confirmation: a question with two answers is exactly what a
  /// dialog is for, and a sheet would be too easy to dismiss by accident.
  final bool staysDialogOnPhone;

  /// Shows a phone a page rather than a card: the screen edge to edge, an
  /// arrow for the way back, the title set large, and only the commit in the
  /// footer. For a step in a flow — adding a server — where each step is a
  /// place you move between rather than a box over the app.
  ///
  /// When a page has more than one action, the first is taken to be the way
  /// back and is left to the arrow; a single action is the way back itself.
  final bool pageOnPhone;

  /// Renders as the body of a **bottom sheet** on a phone: a grabber, the
  /// header, and content only as tall as it needs to be, up to
  /// [_sheetMaxFraction] of the window.
  ///
  /// For a modal that is a *glance* rather than a task — a profile, which is
  /// five facts and two buttons. The full-screen phone branch would leave
  /// that as a header at the top of 400px of nothing, and it would cover the
  /// message you opened it from, which is the thing that made you curious.
  /// Opening it as a sheet is the caller's job ([showModalBottomSheet]
  /// supplies the surface and the radius); this only draws what goes inside.
  final bool sheetOnPhone;

  /// What the arrow does on a [pageOnPhone] page. Closes the modal if null.
  final VoidCallback? onBack;

  const AppModal({
    super.key,
    required this.title,
    this.subtitle,
    this.titleIcon,
    this.count,
    this.headerActions = const [],
    this.content,
    this.error,
    this.body,
    this.actions,
    this.maxWidth = 448,
    this.maxHeight,
    this.staysDialogOnPhone = false,
    this.pageOnPhone = false,
    this.sheetOnPhone = false,
    this.onBack,
  }) : assert(
         (content == null) != (body == null),
         'Give a modal a content form or a self-scrolling body, not both',
       );

  /// [content] with the [error] banner above it, when there is one.
  Widget? get _form => error == null || content == null
      ? content
      : Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          spacing: 12,
          children: [
            MessageBanner(message: error!, kind: MessageBannerKind.error),
            content!,
          ],
        );

  @override
  Widget build(BuildContext context) {
    if (context.layoutMode.isCompact && !staysDialogOnPhone) {
      if (sheetOnPhone) return _buildSheetForPhone(context);
      return pageOnPhone
          ? _buildPageForPhone(context)
          : _buildForPhone(context);
    }
    final themeState = context.theme;
    final borderColor = themeState.borderPrimary;

    return Dialog(
      // The design puts dialogs on the *panel* surface, with the shadow
      // doing the lifting — elevated is reserved for menus and popovers,
      // which open on top of dialogs and need to out-rank them.
      backgroundColor: themeState.bgSecondary,
      // Flutter's default inset is 40 a side, which is a tenth of a phone
      // spent on margin before the dialog's own padding starts. [maxWidth]
      // still decides the size wherever there is room for it; this only
      // changes what "no room" leaves behind.
      insetPadding: EdgeInsets.symmetric(
        horizontal: context.layoutMode.isCompact ? K.panelGutter * 1.6 : 40,
        vertical: 24,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(K.radiusCard),
        side: BorderSide(color: themeState.borderElevated),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight:
              maxHeight ??
              MediaQuery.sizeOf(context).height * _maxHeightFraction,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppModalHeader(
              title: title,
              subtitle: subtitle,
              titleIcon: titleIcon,
              count: count,
              actions: headerActions,
            ),
            Divider(height: 1, color: borderColor),
            Flexible(
              child:
                  body ??
                  SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 18,
                    ),
                    child: _form,
                  ),
            ),
            if (actions != null) ...[
              Divider(height: 1, color: borderColor),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                child: ButtonFooter(buttons: actions!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
