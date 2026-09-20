import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/classes/bot_manifest.dart';
import '../../../../data/classes/directory_tags.dart';
import '../../../../data/classes/public_bot.dart';
import '../../../../data/constants.dart';
import '../../../../logic/cubits/public_bots/public_bots_cubit.dart';
import '../../../../logic/helper_methods.dart';
import '../../../common/app_button.dart';
import '../../../common/app_modal.dart';
import '../../../common/app_text_field.dart';
import '../../../common/hint_card.dart';
import '../../../common/message_banner.dart';
import '../../../common/tag_editor.dart';
import '../../settings/widgets/setting_toggle_row.dart';
import 'widgets/bot_manifest_editor.dart';

/// Listing a bot in the directory, or editing a listing already there.
///
/// Over the widget budget and one job: it is a form, and every line of it is
/// a field, that field's validation, or the sentence explaining why the field
/// is asked for. Splitting the body out would put the controllers in one file
/// and the widgets that own them in another.
///
/// Nothing here is checked by central, and the form says so. What it asks for
/// is the minimum somebody needs to decide whether to run a stranger's
/// program: what it is called, what it does, and **where the code is** — the
/// last of which is required, because it is the only claim on the row anybody
/// can go and verify.
class BotListingFormModal extends StatefulWidget {
  /// The listing being edited, or null to create one.
  final PublicBot? editing;

  final VoidCallback onCancel;
  final VoidCallback onSaved;

  const BotListingFormModal({
    super.key,
    this.editing,
    required this.onCancel,
    required this.onSaved,
  });

  @override
  State<BotListingFormModal> createState() => _BotListingFormModalState();
}

class _BotListingFormModalState extends State<BotListingFormModal> {
  late final _nameCtrl = TextEditingController(text: widget.editing?.name);
  late final _sourceCtrl = TextEditingController(
    text: widget.editing?.sourceUrl,
  );
  late final _descriptionCtrl = TextEditingController(
    text: widget.editing?.description,
  );
  final _tagCtrl = TextEditingController();

  late List<String> _tags = widget.editing?.tags ?? const [];
  late BotManifest _manifest = widget.editing?.manifest ?? BotManifest.empty;
  late bool _isListed = widget.editing?.isListed ?? true;

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _sourceCtrl.dispose();
    _descriptionCtrl.dispose();
    _tagCtrl.dispose();
    super.dispose();
  }

  /// The column's rule, mirrored so a bad URL is refused while it is being
  /// typed rather than by a CHECK on save.
  static final _https = RegExp(r'^https://[^ ]+$');

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final source = _sourceCtrl.text.trim();

    if (name.isEmpty) {
      setState(() => _error = 'Give the bot a name.');
      return;
    }
    if (!_https.hasMatch(source) || source.length > PublicBot.maxSourceUrl) {
      setState(
        () => _error =
            'The source has to be an https link, under '
            '${PublicBot.maxSourceUrl} characters. It is the only thing on '
            'the listing anybody can check.',
      );
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final description = _descriptionCtrl.text.trim();
    final cubit = context.read<PublicBotsCubit>();
    final saved = await cubit.publish(
      id: widget.editing?.id,
      name: name,
      sourceUrl: source,
      description: description.isEmpty ? null : description,
      iconUrl: widget.editing?.iconUrl,
      tags: DirectoryTags.withPending(_tags, _tagCtrl.text),
      // Omitted entirely when empty, so an author who filled nothing in gets
      // a null column rather than `{"commands":[]}` — which the browser would
      // have to tell apart from a bot that really answers to nothing.
      manifest: _manifest.commands.isEmpty && _manifest.dataUse == null
          ? null
          : _manifest.toJson(),
      isListed: _isListed,
    );
    if (!mounted) return;

    if (saved == null) {
      setState(() {
        _saving = false;
        _error = cubit.state.error;
      });
      return;
    }

    HelperMethods.showSuccess(
      message: _isListed
          ? '${saved.name} is in the bot browser'
          : '${saved.name} is saved, and hidden',
    );
    widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.editing != null;

    return AppModal(
      pageOnPhone: true,
      onBack: widget.onCancel,
      title: editing ? 'Edit listing' : 'List a bot',
      subtitle: 'Anyone with a Rift account can find it',
      maxWidth: K.dialogWidth,
      content: _form(),
      actions: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.secondary,
          onPressed: _saving ? null : widget.onCancel,
        ),
        AppButton(
          label: editing ? 'Save' : 'List it',
          isLoading: _saving,
          onPressed: _saving ? null : _save,
        ),
      ],
    );
  }

  Widget _form() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_error != null) ...[
          MessageBanner(message: _error!, kind: MessageBannerKind.error),
          const SizedBox(height: 16),
        ],
        AppTextField(
          controller: _nameCtrl,
          label: 'Name',
          hint: 'Dicebot',
          enabled: !_saving,
          autofocus: true,
          maxLength: 64,
        ),
        const SizedBox(height: 16),
        AppTextField(
          controller: _sourceCtrl,
          label: 'Source',
          hint: 'https://github.com/you/dicebot',
          enabled: !_saving,
          keyboardType: TextInputType.url,
          maxLength: PublicBot.maxSourceUrl,
        ),
        const SizedBox(height: 16),
        AppTextField(
          controller: _descriptionCtrl,
          label: 'Description',
          hint: 'What it does, in a sentence or two',
          enabled: !_saving,
          maxLines: 3,
          maxLength: PublicBot.maxDescription,
        ),
        const SizedBox(height: 16),
        TagEditor(
          controller: _tagCtrl,
          tags: _tags,
          onChanged: (tags) => setState(() => _tags = tags),
          enabled: !_saving,
        ),
        const SizedBox(height: 16),
        BotManifestEditor(
          manifest: _manifest,
          enabled: !_saving,
          onChanged: (manifest) => _manifest = manifest,
        ),
        const SizedBox(height: 16),
        SettingToggleRow(
          title: 'Show it in the browser',
          // Delisting keeps the row and its likes, which is the difference
          // between hiding a bot for a week and giving up its listing.
          description: 'Off keeps the listing and its likes, hidden',
          value: _isListed,
          onChanged: _saving ? null : (v) => setState(() => _isListed = v),
        ),
        const SizedBox(height: 8),
        const HintCard(
          icon: Icons.visibility_outlined,
          text:
              'Rift checks none of this. What makes a listing worth anything '
              'is the source link — somebody deciding whether to run your bot '
              'has nothing else to go on, and the ones that get liked are the '
              'ones people could read first.',
        ),
      ],
    );
  }
}
