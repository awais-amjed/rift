import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:toastification/toastification.dart';

import '../../../../../../../../../logic/cubits/dm/dm_cubit.dart';
import '../../../../../../../../../logic/helper_methods.dart';
import '../../../../../../../../common/app_text_field.dart';

/// A message box on the member card: a server DM to them, without leaving
/// the call, or the stream being watched, for their conversation.
///
/// Enter sends and Shift+Enter starts a new line, as in the composer. No
/// send button: beside a box this small it read as clutter, and Enter is
/// how the composer sends too. The words stay in the box until the server has the
/// message, so a refusal loses nothing.
class MemberCardMessage extends StatefulWidget {
  final String userId;
  final String name;

  const MemberCardMessage({
    super.key,
    required this.userId,
    required this.name,
  });

  @override
  State<MemberCardMessage> createState() => _MemberCardMessageState();
}

class _MemberCardMessageState extends State<MemberCardMessage> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canSend => !_sending && _controller.text.trim().isNotEmpty;

  Future<void> _send() async {
    if (!_canSend) return;
    final text = _controller.text;
    setState(() => _sending = true);
    final error = await context.read<DmCubit>().sendQuickDm(
      peerId: widget.userId,
      peerName: widget.name,
      text: text,
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (error != null) {
      HelperMethods.showToast(
        title: 'Message not sent',
        description: error,
        type: ToastificationType.error,
      );
      return;
    }
    // Only what was sent: anything typed while it was on its way stays.
    if (_controller.text == text) _controller.clear();
    HelperMethods.showToast(
      title: 'Sent',
      description: 'In your DMs with ${widget.name}.',
      type: ToastificationType.success,
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.enter &&
        event.logicalKey != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    if (HardwareKeyboard.instance.isShiftPressed) return KeyEventResult.ignored;
    _send();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: _onKey,
      child: AppTextField(
        controller: _controller,
        hint: 'Message ${widget.name}',
        minLines: 1,
        maxLines: 3,
      ),
    );
  }
}
