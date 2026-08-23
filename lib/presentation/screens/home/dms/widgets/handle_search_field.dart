import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/dm_conversation.dart';
import '../../../../../logic/cubits/central_dm/central_dm_cubit.dart';
import '../../../../../logic/cubits/dm/dm_cubit.dart';
import '../../../../common/search_dropdown_field.dart';
import '../../../../common/search_result_row.dart';

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
      itemBuilder: (context, result, dismiss) => SearchResultRow(
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
