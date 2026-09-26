import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/constants.dart';
import '../../../../data/enums/listing_kind.dart';
import '../../../../logic/cubits/moderation/moderation_cubit.dart';
import '../../../common/context_menu/context_menu_item.dart';
import '../../../common/context_menu/context_menu_overlay.dart';
import '../../../common/context_menu/context_menu_panel.dart';
import '../../../common/show_custom_dialog.dart';
import '../../../theme/theme_context.dart';
import 'moderation_reason_dialog.dart';
import 'report_listing_dialog.dart';

/// The "⋯" on a directory listing: Report, and for a moderator, Hide.
///
/// Absent when it would hold nothing — your own listing, if you do not
/// moderate — rather than a button that opens an empty menu.
class ListingMenuButton extends StatefulWidget {
  final ListingKind kind;
  final String listingId;
  final String name;
  final String ownerId;

  /// After a moderator hid it, so the list it sits in can drop it.
  final VoidCallback? onHidden;

  const ListingMenuButton({
    super.key,
    required this.kind,
    required this.listingId,
    required this.name,
    required this.ownerId,
    this.onHidden,
  });

  @override
  State<ListingMenuButton> createState() => _ListingMenuButtonState();
}

class _ListingMenuButtonState extends State<ListingMenuButton> {
  final ContextMenuOverlay _menu = ContextMenuOverlay();

  @override
  void dispose() {
    _menu.dismiss();
    super.dispose();
  }

  bool get _isOwn =>
      widget.ownerId == context.read<ModerationCubit>().currentUserId;

  void _open(bool isModerator) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final cubit = context.read<ModerationCubit>();
    _menu.show(
      context,
      _ListingMenu(
        cubit: cubit,
        kind: widget.kind,
        listingId: widget.listingId,
        name: widget.name,
        canReport: !_isOwn,
        canHide: isModerator,
        onHidden: widget.onHidden,
      ),
      box.localToGlobal(Offset(0, box.size.height)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isModerator = context.select<ModerationCubit, bool>(
      (c) => c.state.isModerator,
    );
    if (_isOwn && !isModerator) return const SizedBox.shrink();

    final theme = context.theme;
    return IconButton(
      tooltip: 'More',
      mouseCursor: WidgetStateMouseCursor.clickable,
      icon: const Icon(Icons.more_horiz_rounded, size: K.iconButton),
      color: theme.textTertiary,
      onPressed: () => _open(isModerator),
    );
  }
}

class _ListingMenu extends StatelessWidget {
  final ModerationCubit cubit;
  final ListingKind kind;
  final String listingId;
  final String name;
  final bool canReport;
  final bool canHide;
  final VoidCallback? onHidden;

  const _ListingMenu({
    required this.cubit,
    required this.kind,
    required this.listingId,
    required this.name,
    required this.canReport,
    required this.canHide,
    this.onHidden,
  });

  Future<void> _hide(BuildContext context) async {
    final hidden = await showDialogFromMenu<bool>(
      context: context,
      build: (_) => ModerationReasonDialog(
        title: 'Hide $name?',
        message:
            'It leaves the directory for everyone, its reports are closed and '
            'its icon is deleted. Its owner still sees it, with your reason. '
            'You can show it again from Settings → Moderation.',
        confirmLabel: 'Hide',
        onConfirm: (reason) => cubit.hideById(kind, listingId, reason: reason),
      ),
    );
    if (hidden == true) onHidden?.call();
  }

  @override
  Widget build(BuildContext context) {
    return ContextMenuPanel(
      children: [
        if (canReport)
          ContextMenuItem(
            icon: Icons.flag_outlined,
            label: 'Report…',
            onTap: () => showDialogFromMenu<void>(
              context: context,
              build: (_) => ReportListingDialog(
                name: name,
                onSend: (reason, details) => cubit.report(
                  kind: kind,
                  listingId: listingId,
                  reason: reason,
                  details: details,
                ),
              ),
            ),
          ),
        if (canHide)
          ContextMenuItem(
            icon: Icons.visibility_off_outlined,
            label: 'Hide from directory…',
            isDangerous: true,
            onTap: () => _hide(context),
          ),
      ],
    );
  }
}
