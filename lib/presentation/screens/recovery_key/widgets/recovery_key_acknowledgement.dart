import 'package:flutter/material.dart';

import '../../../common/checkbox_row.dart';

/// The "I have saved it" confirmation, as a row you press anywhere on.
///
/// A checkbox rather than a button alone because the cost of the mistake is
/// unrecoverable and lands months later. This is the last point at which the
/// truth can be told to somebody who can still act on it.
class RecoveryKeyAcknowledgement extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const RecoveryKeyAcknowledgement({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return CheckboxRow(
      label: 'I have saved my recovery key somewhere safe.',
      value: value,
      onChanged: onChanged,
    );
  }
}
