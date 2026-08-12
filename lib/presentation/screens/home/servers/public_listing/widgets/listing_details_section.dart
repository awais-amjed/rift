import 'package:flutter/material.dart';

import '../../../../../../data/classes/public_server.dart';
import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../common/app_text_field.dart';
import '../../../../../common/tag_editor.dart';
import '../../../../../theme/app_text.dart';
import '../../../../settings/widgets/section_title.dart';

/// What a stranger reads in the browser before deciding to join: the name, a
/// sentence about the place, and the tags they might have filtered by.
///
/// The name is separate from the server's own name on purpose. The one on the
/// server is what members see in their rail; this one is an advertisement, and
/// an admin should be able to change either without the other following.
class ListingDetailsSection extends StatelessWidget {
  final TextEditingController nameCtrl;
  final TextEditingController descriptionCtrl;
  final TextEditingController tagCtrl;
  final List<String> tags;
  final ValueChanged<List<String>> onTagsChanged;
  final ThemeState themeState;
  final bool enabled;

  const ListingDetailsSection({
    super.key,
    required this.nameCtrl,
    required this.descriptionCtrl,
    required this.tagCtrl,
    required this.tags,
    required this.onTagsChanged,
    required this.themeState,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SectionTitle(label: 'How it appears', themeState: themeState),
        const SizedBox(height: 4),
        Text(
          'This is what someone sees in the browser before they know anything '
          'else about the place.',
          style: AppText.label.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w400,
            color: themeState.textTertiary,
          ),
        ),
        const SizedBox(height: 14),
        AppTextField(
          controller: nameCtrl,
          label: 'Listed name',
          hint: 'My Server',
          enabled: enabled,
        ),
        const SizedBox(height: 16),
        AppTextField(
          controller: descriptionCtrl,
          label: 'Description',
          hint: 'What happens here, in a sentence or two',
          enabled: enabled,
          maxLines: 3,
          maxLength: PublicServer.maxDescription,
        ),
        const SizedBox(height: 16),
        TagEditor(
          controller: tagCtrl,
          tags: tags,
          onChanged: onTagsChanged,
          themeState: themeState,
          enabled: enabled,
        ),
      ],
    );
  }
}
