import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/tap_to_focus.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';

/// The search row at the top of Manage server › Members.
///
/// It exists because the list below it is a page rather than the whole roster
/// (`011_directory.sql`). Scrolling to somebody is fine at fifty members and useless
/// at five thousand, so the way to reach a person is to name them — and the
/// answer comes from the database, which is the only thing that has seen all of
/// them.
///
/// Debounced rather than searching per keystroke: the field is for typing a
/// name into, and a request per letter would spend five round trips answering
/// about prefixes nobody meant.
class MembersSearchField extends StatefulWidget {
  /// Fires with the settled query — empty when the field is cleared, which the
  /// dialog reads as "go back to the paged list".
  final ValueChanged<String> onChanged;

  const MembersSearchField({super.key, required this.onChanged});

  @override
  State<MembersSearchField> createState() => _MembersSearchFieldState();
}

class _MembersSearchFieldState extends State<MembersSearchField> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // The ring follows focus, as the other search fields' does.
    _focusNode.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _timer?.cancel();
    // Clearing takes effect at once. Waiting a quarter second to go back to a
    // list that is already loaded is a pause with nothing behind it.
    if (value.trim().isEmpty) {
      widget.onChanged('');
    } else {
      _timer = Timer(K.searchDebounce, () => widget.onChanged(value));
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    // No side inset of its own: the page it sits on already gives it one,
    // and a second 20px left the box narrower than the list it filters.
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: TapToFocus(focusNode: _focusNode, child: _box(theme)),
    );
  }

  Widget _box(ThemeState theme) {
    return Container(
      height: K.fieldHeight,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: theme.bgHover,
        borderRadius: BorderRadius.circular(K.radiusRow),
        border: Border.all(
          color: _focusNode.hasFocus
              ? theme.primary.withValues(alpha: 0.55)
              : theme.borderPrimary,
        ),
      ),
      child: Row(
        spacing: 8,
        children: [
          Icon(
            Icons.search_rounded,
            size: K.iconRow,
            color: theme.textQuaternary,
          ),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              onChanged: _onChanged,
              style: AppText.secondary.copyWith(color: theme.textPrimary),
              cursorColor: theme.primary,
              cursorWidth: 1.5,
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: 'Search members…',
                hintStyle: AppText.secondary.copyWith(
                  color: theme.textQuaternary,
                ),
              ),
            ),
          ),
          if (_controller.text.isNotEmpty)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () {
                  _controller.clear();
                  _onChanged('');
                },
                child: Icon(
                  Icons.close_rounded,
                  size: K.iconInline,
                  color: theme.textQuaternary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
