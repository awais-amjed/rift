part of 'chat_message_list.dart';

/// Moving the list: to the message a quote answers, paging it in first when
/// it is further back, and back to the live end.
mixin _MessageListJumpsMixin on State<ChatMessageList> {
  /// Implemented by the State class, which owns the render list this reads.
  double? _fractionOf(String rowId);

  /// Scrolling to a message a reply points at.
  final MessageJumper _jumper = MessageJumper();

  /// The row a jump last landed on, and a token that changes every time one
  /// does — so tapping the same quote twice flashes twice.
  String? _flashRowId;
  int _flashToken = 0;

  /// Back to the live end, and to the *bottom* of it.
  ///
  /// The scroll controller outlives the list, so replacing a history window
  /// with the newest page leaves the view at whatever offset the window was
  /// scrolled to — which lands the reader somewhere in the middle of the
  /// present having asked to be taken to the end of it.
  Future<void> _returnToPresent() async {
    final returnToPresent = widget.onReturnToPresent;
    if (returnToPresent == null) return;
    await returnToPresent();

    // Twice, a frame apart. Returning emits more than once — the new page,
    // then the flag that clears the spinner — and a single jump can land
    // between them, against a list that is about to be replaced. Zero is
    // the newest message either way, because the list is reversed, so the
    // second jump is free when the first one already worked.
    for (var attempt = 0; attempt < 2; attempt++) {
      if (!mounted) return;
      await SchedulerBinding.instance.endOfFrame;
      final controller = widget.controller;
      if (!mounted || controller == null || !controller.hasClients) return;
      if (controller.offset != 0) controller.jumpTo(0);
    }
  }

  /// Go to what a reply answers: page it into the list if it is further
  /// back than the loaded page, then scroll to it.
  ///
  /// [loaded] is true when the message is already in the list, which is the
  /// ordinary case and skips the paging entirely.
  Future<void> _goToOriginal(String messageId, {required bool loaded}) async {
    if (!loaded) {
      final page = widget.onShowAround;
      if (page == null) return;
      final reached = await page(messageId);
      if (!mounted) return;
      if (!reached) {
        HelperMethods.showToast(
          title: 'Could not go there',
          description: 'That message could not be loaded.',
        );
        return;
      }
      // The list has grown by however many pages that took, so let it lay
      // out before asking where anything is.
      await SchedulerBinding.instance.endOfFrame;
      if (!mounted) return;
    }
    // Resolved here, not by the caller, and by *message* id rather than row
    // id: a message the server has just acked is still drawn under the local
    // id it was sent with ([ChatMessage.rowId]), which is what the jumper's
    // keys are filed by and is not what a reply points at.
    final row = widget.messages
        .where((message) => message.id == messageId)
        .firstOrNull;
    if (row == null) return;
    await _jumpTo(row.rowId);
  }

  /// Go to the message [rowId], and mark it once we are there.
  ///
  /// The mark is set on arrival rather than on the press: a jump that could
  /// not get there would otherwise tint a row nobody is looking at, and the
  /// reader would go hunting for a highlight somewhere off screen.
  Future<void> _jumpTo(String rowId) async {
    final arrived = await _jumper.jumpTo(
      rowId,
      controller: widget.controller,
      fractionOf: _fractionOf,
    );
    if (!arrived || !mounted) return;
    setState(() {
      _flashRowId = rowId;
      _flashToken++;
    });
  }
}
