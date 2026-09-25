import 'package:flutter/material.dart';

import '../../data/constants.dart';
import '../../logic/services/masked_email.dart';
import '../theme/theme_context.dart';

/// An email address, hidden until asked for.
///
/// The backup pages say who is signed in, and a settings page is exactly
/// what ends up on a shared screen. So the address is dots by default, the
/// first letter and the domain kept so the reader knows which account it
/// is, and an eye at the end shows the whole thing for as long as this
/// widget is on screen. Nothing is remembered: the next visit starts hidden.
class MaskedEmailText extends StatefulWidget {
  final String? email;
  final TextStyle style;

  /// Words before the address, in the same style.
  final String prefix;

  const MaskedEmailText({
    super.key,
    required this.email,
    required this.style,
    this.prefix = '',
  });

  @override
  State<MaskedEmailText> createState() => _MaskedEmailTextState();
}

class _MaskedEmailTextState extends State<MaskedEmailText> {
  bool _shown = false;

  @override
  Widget build(BuildContext context) {
    final email = widget.email;
    if (email == null) {
      return Text('${widget.prefix}unknown', style: widget.style);
    }
    final themeState = context.theme;
    return Row(
      children: [
        Expanded(
          child: Text(
            '${widget.prefix}${_shown ? email : MaskedEmail.of(email)}',
            style: widget.style,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Tooltip(
          message: _shown ? 'Hide address' : 'Show address',
          waitDuration: K.tooltipDelay,
          child: InkWell(
            mouseCursor: WidgetStateMouseCursor.clickable,
            borderRadius: BorderRadius.circular(K.radiusPill),
            onTap: () => setState(() => _shown = !_shown),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                _shown
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: K.iconRow,
                color: themeState.textTertiary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
