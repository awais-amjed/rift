import 'package:flutter/material.dart';

import '../../data/classes/public_server.dart';
import '../../data/constants.dart';
import '../../logic/cubits/theme/theme_cubit.dart';
import '../theme/app_text.dart';
import 'app_button.dart';
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
///
/// **[controller] belongs to the caller**, which is the whole point: a tag
/// typed and not turned into a chip used to be invisible to the save, so
/// filling the box and pressing Save published nothing. The form that saves
/// has to be able to read what is still in the box — see
/// [ServerTags.withPending].
class TagEditor extends StatelessWidget {
  final TextEditingController controller;
  final List<String> tags;
  final ValueChanged<List<String>> onChanged;
  final ThemeState themeState;
  final bool enabled;

  const TagEditor({
    super.key,
    required this.controller,
    required this.tags,
    required this.onChanged,
    required this.themeState,
    this.enabled = true,
  });

  bool get _full => tags.length >= ServerTags.maxCount;

  void _add() {
    final next = ServerTags.withPending(tags, controller.text);
    controller.clear();
    // Called even when nothing was added — a rejected entry (blank, duplicate,
    // one too many) still emptied the box, and the Add button's state depends
    // on what is in it.
    onChanged(next);
  }

  void _remove(String tag) => onChanged(tags.where((t) => t != tag).toList());

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (tags.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final tag in tags)
                _TagChip(
                  tag: tag,
                  themeState: themeState,
                  onRemove: enabled ? () => _remove(tag) : null,
                ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        Row(
          // The field carries a label above it, so the two line up on their
          // bottoms rather than their tops.
          crossAxisAlignment: CrossAxisAlignment.end,
          spacing: 8,
          children: [
            Expanded(
              child: AppTextField(
                controller: controller,
                label: 'Tags',
                hint: _full
                    ? '${ServerTags.maxCount} is the most a listing carries'
                    : 'gaming, board-games',
                enabled: enabled && !_full,
                onEditingComplete: _add,
                onChanged: (_) => onChanged(tags),
              ),
            ),
            AppButton(
              label: 'Add',
              variant: AppButtonVariant.secondary,
              height: K.fieldHeight,
              onPressed: enabled && !_full && controller.text.trim().isNotEmpty
                  ? _add
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'How people filter the browser. Lowercase, no spaces — anything else '
          'is folded into that shape. Whatever is still in the box when you '
          'save is added too.',
          style: AppText.label.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w400,
            color: themeState.textTertiary,
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
          // The chip's tint is its own fill, so the ink for the one hit target
          // on it needs a surface above that fill rather than behind it.
          Material(
            type: MaterialType.transparency,
            child: InkWell(
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
          ),
        ],
      ),
    );
  }
}
