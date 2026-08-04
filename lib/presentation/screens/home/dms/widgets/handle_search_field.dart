import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/dm_conversation.dart';
import '../../../../../logic/cubits/central_dm/central_dm_cubit.dart';
import '../../../../../logic/cubits/dm/dm_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/search_dropdown_field.dart';
import '../../../../common/squircle_avatar.dart';
import '../../../../theme/app_text.dart';

/// Finds people in the central directory by handle.
///
/// No results without a query: the directory is everyone on central, and
/// there is nothing useful to show for an empty search.
class HandleSearchField extends StatelessWidget {
  /// Owned by the panel above, which pre-fills and focuses it.
  final TextEditingController controller;
  final FocusNode focusNode;

  const HandleSearchField({
    super.key,
    required this.controller,
    required this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    return SearchDropdownField<DmConversation>(
      controller: controller,
      focusNode: focusNode,
      hintText: 'Find by handle…',
      emptyMessage: 'Nobody found with that handle.',
      onSearch: context.read<CentralDmCubit>().searchHandles,
      itemBuilder: (context, result, dismiss) => _ResultRow(
        name: '@${result.peerName}',
        seed: result.peerId,
        onTap: () {
          dismiss();
          // Only one DM surface is open at a time.
          context.read<DmCubit>().closeConversation();
          context.read<CentralDmCubit>().openConversation(
            peerId: result.peerId,
            peerHandle: result.peerName,
            peerChatKey: result.peerChatPublicKey,
            peerSigningKey: result.peerSigningPublicKey,
          );
        },
      ),
    );
  }
}

/// One person in a DM search drop-down.
class _ResultRow extends StatelessWidget {
  final String name;
  final String seed;
  final VoidCallback onTap;

  const _ResultRow({
    required this.name,
    required this.seed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeCubit>().state;
    final radius = BorderRadius.circular(9);

    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        hoverColor: themeState.bgHover,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            spacing: 9,
            children: [
              SquircleAvatar(name: name, seed: seed, size: 26),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.row.copyWith(
                    fontSize: 13,
                    color: themeState.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
