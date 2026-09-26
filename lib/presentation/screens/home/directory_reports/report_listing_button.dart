import 'package:flutter/material.dart';

import '../../../../data/constants.dart';
import '../../../common/show_custom_dialog.dart';
import '../../../theme/theme_context.dart';
import 'report_listing_dialog.dart';

/// The flag on a directory listing, which opens [ReportListingDialog].
///
/// A button rather than a "⋯" menu: reporting is the one thing a listing
/// offers besides joining it, and a menu with one row is a click spent
/// confirming the only choice there was. Not drawn on your own listing — the
/// way to take that down is to remove it.
class ReportListingButton extends StatelessWidget {
  final String name;
  final ReportSender onReport;

  const ReportListingButton({
    super.key,
    required this.name,
    required this.onReport,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return IconButton(
      tooltip: 'Report',
      mouseCursor: WidgetStateMouseCursor.clickable,
      icon: const Icon(Icons.flag_outlined, size: K.iconButton),
      color: theme.textTertiary,
      onPressed: () => showCustomDialog<void>(
        context: context,
        build: (_) => ReportListingDialog(name: name, onSend: onReport),
      ),
    );
  }
}
