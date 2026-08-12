import 'package:flutter/material.dart';

import '../../data/classes/public_server.dart';
import '../../data/constants.dart';
import '../../logic/cubits/theme/theme_cubit.dart';
import '../theme/app_text.dart';
import 'app_text_field.dart';

/// The tags on a public listing: the ones already chosen, and a field to add
/// another.
///
/// Shared rather than owned by the publish dialog — a server's tags are also
/// set on the step right after it is created, and two copies of a normalising
/// field would drift.
///
/// Free slugs rather than a fixed category list, and the field normalises what
/// you type ([ServerTags.normalise]) instead of refusing it — "Board Games"
/// becomes `board-games`, because the shape is the database's business and not
/// something an admin should have to learn.
class TagEditor extends StatefulWidget {
  final List<String> tags;
  final ValueChanged<List<String>> onChanged;
  final ThemeState themeState;
  final bool enabled;

  const TagEditor({
    super.key,
    required this.tags,
    required this.onChanged,
    required this.themeState,
    this.enabled = true,
  });

  @override
  State<TagEditor> createState() => _TagEditorState();
}

class _TagEditorState extends State<TagEditor> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add() {
    final tag = ServerTags.normalise(_controller.text);
    if (tag == null || widget.tags.contains(tag)) {
      _controller.clear();
      return;
    }
    if (widget.tags.length >= ServerTags.maxCount) return;
    widget.onChanged([...widget.tags, tag]);
    _controller.clear();
  }

  void _remove(String tag) =>
      widget.onChanged(widget.tags.where((t) => t != tag).toList());

  @override
  Widget build(BuildContext context) {
    final full = widget.tags.length >= ServerTags.maxCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.tags.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final tag in widget.tags)
                _TagChip(
                  tag: tag,
                  themeState: widget.themeState,
                  onRemove: widget.enabled ? () => _remove(tag) : null,
                ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        AppTextField(
          controller: _controller,
          label: 'Tags',
          hint: full
              ? '${ServerTags.maxCount} is the most a listing may carry'
              : 'gaming, board-games — press Enter to add',
          enabled: widget.enabled && !full,
          onEditingComplete: _add,
        ),
        const SizedBox(height: 6),
        Text(
          'Tags are how people filter the browser. Lowercase, no spaces — '
          'anything else is folded into that shape.',
          style: AppText.label.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w400,
            color: widget.themeState.textTertiary,
          ),
        ),
      ],
    );
  }
}

/// One chosen tag, with the way to drop it again.
class _TagChip extends StatelessWidget {
  final String tag;
  final ThemeState themeState;
  final VoidCallback? onRemove;

  const _TagChip({
    required this.tag,
    required this.themeState,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 10, right: 4, top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: themeState.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(K.radiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          Text(
            tag,
            style: AppText.label.copyWith(
              fontWeight: FontWeight.w600,
              color: themeState.primary,
            ),
          ),
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(K.radiusPill),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(
                Icons.close_rounded,
                size: 13,
                color: themeState.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
