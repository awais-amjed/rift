import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../logic/cubits/central_dm/central_dm_cubit.dart';
import '../../../../../common/app_button.dart';
import '../../../../../common/app_text_field.dart';
import '../../../../../theme/app_text.dart';
import '../../../../../theme/theme_context.dart';

/// Add somebody by typing their handle in full and pressing a button.
///
/// It used to be a search drop-down: three letters and the directory answered
/// with a list, and picking a name from it sent the request. That made every
/// account on central browsable by anyone who had signed up, and it made
/// "send a friend request" something you did by accident, to whoever happened
/// to be first in a list.
///
/// So there is no list. You type a handle you already know — because somebody
/// told it to you, which is the only way handles travel — and the server
/// answers by either sending the request or saying nobody is using it. The
/// lookup and the request are the same call (central migration 012), so this
/// cannot be used to check whether a handle exists without also knocking.
///
/// The button is not merely decoration over the same behaviour: it is what
/// makes the request a thing you decided to do. Enter does it too, because a
/// field you have finished typing into is a decision as well.
class AddFriendField extends StatefulWidget {
  const AddFriendField({super.key});

  @override
  State<AddFriendField> createState() => _AddFriendFieldState();
}

class _AddFriendFieldState extends State<AddFriendField> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Seeded by the cubit when you arrive from a member's "Add on Central".
  /// Their server display name is a *guess* at their handle — the two
  /// identities are unrelated — so it is selected rather than merely inserted,
  /// and the button is left unpressed. The user confirms or types over it.
  void _consumeSeededQuery(String query) {
    _controller.text = query;
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: query.length,
    );
    _focusNode.requestFocus();
    context.read<CentralDmCubit>().setHandleQuery(null);
  }

  Future<void> _submit() async {
    if (_sending || _controller.text.trim().isEmpty) return;
    setState(() => _sending = true);
    final sent = await context.read<CentralDmCubit>().addFriendByHandle(
      _controller.text,
    );
    if (!mounted) return;
    // Cleared only when it worked. A handle that was refused is one the user
    // may have mistyped, and retyping something you can no longer see is
    // worse than fixing what is in front of you.
    if (sent) _controller.clear();
    setState(() => _sending = false);
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;

    return BlocListener<CentralDmCubit, CentralDmState>(
      listenWhen: (a, b) => a.handleQuery != b.handleQuery,
      listener: (context, state) {
        final query = state.handleQuery;
        if (query != null) _consumeSeededQuery(query);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            spacing: 8,
            children: [
              Expanded(
                child: AppTextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  hint: 'Enter a handle, e.g. river_stone',
                  enabled: !_sending,
                  // The shape the column already enforces, applied while
                  // typing: a handle is lowercase and has no spaces in it, so
                  // a capital or a space is a keystroke to absorb rather than
                  // an error to report afterwards.
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_@]')),
                    TextInputFormatter.withFunction(
                      (_, next) => next.copyWith(text: next.text.toLowerCase()),
                    ),
                    LengthLimitingTextInputFormatter(21),
                  ],
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _submit(),
                ),
              ),
              AppButton(
                label: 'Send request',
                isLoading: _sending,
                onPressed: _controller.text.trim().isEmpty ? null : _submit,
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            'Handles are exact. Nobody can be found by searching, and nobody '
            'can message you before you accept.',
            style: AppText.secondary.copyWith(color: themeState.textTertiary),
          ),
        ],
      ),
    );
  }
}
