import 'package:flutter/material.dart';

import '../../../../../common/app_button.dart';
import '../../../../../common/app_text_field.dart';

/// The "name it and make it" line at the top of a channel's webhook list.
///
/// A webhook is created from one field because one field is all it takes: the
/// channel comes from where the dialog was opened and the secret is the
/// server's to mint. Anything else here would be a setting the schema does not
/// have.
class WebhookCreateRow extends StatelessWidget {
  final TextEditingController controller;
  final bool isBusy;

  /// Null while the name is empty or a create is already in flight.
  final VoidCallback? onCreate;
  final ValueChanged<String> onChanged;

  const WebhookCreateRow({
    super.key,
    required this.controller,
    required this.isBusy,
    required this.onChanged,
    this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      controller: controller,
      label: 'New webhook',
      hint: 'GitHub',
      maxLength: 80,
      enabled: !isBusy,
      onChanged: onChanged,
      onSubmitted: (_) => onCreate?.call(),
      trailing: AppButton(
        label: 'Create',
        isLoading: isBusy,
        onPressed: onCreate,
      ),
    );
  }
}
