import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/central_dm/central_dm_cubit.dart';
import '../../../../../logic/services/central_handle.dart';
import '../../../../common/app_button.dart';
import '../../../../common/app_text_field.dart';
import '../../../../common/button_footer.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/custom_colors.dart';
import '../../../../theme/theme_context.dart';

/// Inline claim-a-handle panel, shown when the user is signed in to central
/// but hasn't created a directory profile yet.
class CentralHandlePanel extends StatefulWidget {
  const CentralHandlePanel({super.key});

  @override
  State<CentralHandlePanel> createState() => _CentralHandlePanelState();
}

class _CentralHandlePanelState extends State<CentralHandlePanel> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    final state = context.watch<CentralDmCubit>().state;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pick a handle so people can find you:',
            style: AppText.secondary.copyWith(color: themeState.textTertiary),
          ),
          const SizedBox(height: 8),
          AppTextField(
            controller: _controller,
            hint: 'your_handle',
            onChanged: (_) => context.read<CentralDmCubit>().dismissError(),
          ),
          const SizedBox(height: 6),
          Text(
            CentralHandle.rule,
            style: AppText.secondary.copyWith(color: themeState.textQuaternary),
          ),
          if (state.error != null) ...[
            const SizedBox(height: 6),
            Text(
              state.error!,
              style: AppText.secondary.copyWith(color: CustomColors.error),
            ),
          ],
          const SizedBox(height: 8),
          ButtonFooter(
            buttons: [
              AppButton(
                label: 'Claim handle',
                isLoading: state.claiming,
                onPressed: state.claiming
                    ? null
                    : () => context.read<CentralDmCubit>().claimHandle(
                        _controller.text,
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
