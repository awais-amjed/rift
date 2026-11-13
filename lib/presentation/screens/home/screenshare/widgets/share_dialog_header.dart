import 'package:material_ui/material_ui.dart';

import '../../../../common/app_modal_header_button.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';

/// The top of a page of the share dialog: the way back where there is one, its
/// title, and whichever of refresh and close the page has.
class ShareDialogHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onBack;
  final VoidCallback? onRefresh;
  final VoidCallback? onClose;

  const ShareDialogHeader({
    super.key,
    required this.title,
    this.onBack,
    this.onRefresh,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final back = onBack;
    final refresh = onRefresh;
    final close = onClose;
    return Row(
      spacing: 4,
      children: [
        if (back != null)
          AppModalHeaderButton(
            icon: Icons.arrow_back,
            tooltip: 'Back',
            onPressed: back,
          ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: back == null ? 0 : 4),
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.modalPageTitle.copyWith(
                color: context.theme.textPrimary,
              ),
            ),
          ),
        ),
        if (refresh != null)
          AppModalHeaderButton(
            icon: Icons.refresh,
            tooltip: 'Refresh the list',
            onPressed: refresh,
          ),
        if (close != null)
          AppModalHeaderButton(
            icon: Icons.close,
            tooltip: 'Close',
            onPressed: close,
          ),
      ],
    );
  }
}
