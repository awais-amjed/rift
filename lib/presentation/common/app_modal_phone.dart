part of 'app_modal.dart';

/// Over the widget budget and one job: a modal's phone layout, in its three
/// shapes.
///
/// The three shapes an [AppModal] takes on a phone: a near-full-screen
/// dialog, a bottom sheet, and a page.
///
/// Split out because a phone is a different layout rather than a narrower
/// one — each shape pins the footer where a thumb is, and none of that has
/// anything to say about the desktop dialog.
extension _AppModalPhone on AppModal {
  /// A phone: the whole screen, less a margin, with the footer pinned where a
  /// thumb is.
  ///
  /// A 448px dialog in a 390px window has no margins left to float in, and a
  /// form sized to its content leaves its buttons wherever the last field
  /// happened to end. Filling the screen puts the commit at the bottom every
  /// time, at the taller thumb height, and gives a long form one scroll.
  Widget _buildForPhone(BuildContext context) {
    final themeState = context.theme;
    final borderColor = themeState.borderPrimary;
    final safe = MediaQuery.paddingOf(context);
    const margin = 10.0;

    return Dialog(
      backgroundColor: themeState.bgSecondary,
      insetPadding: EdgeInsets.fromLTRB(
        margin,
        margin + safe.top + titleBarInset(),
        margin,
        margin + safe.bottom,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(K.radiusCard),
        side: BorderSide(color: themeState.borderElevated),
      ),
      child: SizedBox.expand(
        child: Column(
          children: [
            AppModalHeader(
              title: title,
              subtitle: subtitle,
              titleIcon: titleIcon,
              count: count,
              actions: headerActions,
            ),
            Divider(height: 1, color: borderColor),
            Expanded(
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
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: AppButtonHeight(
                  height: K.thumbCtaHeight,
                  child: ButtonFooter(buttons: actions!),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// See [sheetOnPhone].
  ///
  /// No [Dialog] and no surface of its own: the sheet route paints both, so
  /// drawing another here would be a card inside a card.
  Widget _buildSheetForPhone(BuildContext context) {
    final themeState = context.theme;
    final borderColor = themeState.borderPrimary;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight:
            MediaQuery.sizeOf(context).height * AppModal._sheetMaxFraction,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The grabber says the whole sheet is draggable, which is the
          // gesture that dismisses it — there is no other affordance for
          // that, and a sheet you can only close by reaching for the X is a
          // dialog wearing a rounded top.
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: themeState.textPrimary.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(K.radiusPill),
              ),
            ),
          ),
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
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                  // Everything pressable in here is under a thumb, and the
                  // buttons are the reason the sheet was opened.
                  child: AppButtonHeight(
                    height: K.thumbCtaHeight,
                    child: _form!,
                  ),
                ),
          ),
          if (actions != null) ...[
            Divider(height: 1, color: borderColor),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: AppButtonHeight(
                height: K.thumbCtaHeight,
                child: ButtonFooter(buttons: actions!),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// See [pageOnPhone].
  Widget _buildPageForPhone(BuildContext context) {
    final themeState = context.theme;
    final actions = this.actions ?? const <Widget>[];
    final commit = actions.length >= 2 ? actions.last : null;

    final onBack = this.onBack;
    return PopScope(
      // The system back gesture is the arrow: a step goes back a step rather
      // than closing the whole flow out from under it.
      canPop: onBack == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onBack?.call();
      },
      child: Dialog.fullscreen(
        backgroundColor: themeState.bgSecondary,
        child: SafeArea(
          // Clears the window's own title bar as well as the phone's status
          // bar: a full-screen page starts at y=0, and the back arrow below is
          // the first thing the title bar would cover — and swallow the click
          // for.
          minimum: EdgeInsets.only(top: titleBarInset()),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: BackChevronButton(
                    onPressed: onBack ?? () => Navigator.of(context).pop(),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 4,
                  children: [
                    Text(
                      title,
                      style: AppText.modalPageTitle.copyWith(
                        color: themeState.textPrimary,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: AppText.body.copyWith(
                          color: themeState.textTertiary,
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child:
                    body ??
                    SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                      child: _form,
                    ),
              ),
              if (commit != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: AppButtonHeight(
                    height: K.thumbCtaHeight,
                    child: SizedBox(width: double.infinity, child: commit),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
