import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';

/// Who you are on central, under the panel title — and the way to change it.
///
/// The handle is the only piece of a central account the user chose, and it
/// was write-once: the panel that claims one is built only while there isn't
/// one, so a typo was permanent as far as the app was concerned. The claim
/// itself is an upsert and always could be re-run; only a way to ask for it
/// was missing.
///
/// The affordance sits on the handle rather than in a settings page, which is
/// where someone looking to change their name would look, and saves a whole
/// screen for a single field.
class CentralIdentityLine extends StatelessWidget {
  final String? handle;

  /// False while there is no central session at all. The line then says so,
  /// rather than naming an account that isn't there.
  final bool signedIn;

  /// Asked for when the line is tapped. There is nothing to tap without a
  /// handle, so this is only ever called with one already claimed. Null
  /// draws the line alone, with no pencil: a phone's, which sits in a bar
  /// whose own tap opens the switcher, changes it in settings instead
  /// (`HandleSection`).
  final VoidCallback? onChangeHandle;

  const CentralIdentityLine({
    super.key,
    required this.handle,
    this.onChangeHandle,
    this.signedIn = true,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    if (!signedIn) {
      return Row(
        spacing: 5,
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: K.iconTiny,
            color: themeState.textQuaternary,
          ),
          Text(
            'Not signed in',
            style: AppText.label.copyWith(
              fontWeight: FontWeight.w400,
              color: themeState.textTertiary,
            ),
          ),
        ],
      );
    }
    final line = Row(
      spacing: 5,
      children: [
        Icon(Icons.public, size: K.iconTiny, color: themeState.accentBright),
        if (handle != null)
          Flexible(
            child: Text(
              '@$handle',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              // Mono: a handle is an identifier, and it reads as one.
              style: AppText.figure.copyWith(
                fontWeight: FontWeight.w400,
                color: themeState.textTertiary,
              ),
            ),
          ),
        Text(
          handle == null ? 'Rift account' : '· Rift account',
          style: AppText.label.copyWith(
            fontWeight: FontWeight.w400,
            color: themeState.textTertiary,
          ),
        ),
        if (handle != null && onChangeHandle != null)
          Icon(
            Icons.edit_outlined,
            size: K.iconTiny,
            color: themeState.textQuaternary,
          ),
      ],
    );

    if (handle == null || onChangeHandle == null) return line;

    return Tooltip(
      message: 'Change handle',
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        onTap: onChangeHandle,
        borderRadius: BorderRadius.circular(K.radiusRow),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
          child: line,
        ),
      ),
    );
  }
}
