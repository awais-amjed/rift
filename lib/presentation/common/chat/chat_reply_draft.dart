import 'package:flutter/widgets.dart';

import '../../../data/classes/chat_message.dart';

/// The half-written reply a chat view is holding: which message is being
/// answered, and whether sending will ring its author.
///
/// **State of the view, not of the conversation**, and it sits beside the
/// composer's text for that reason — both are what somebody has started and
/// not sent, both live exactly as long as the screen does, and a cubit that
/// held one but not the other would be a draft split across two lifetimes.
///
/// Mixed into all three chat views rather than written three times, because
/// the two rules below are the ones each of them would get subtly different.
mixin ChatReplyDraft<T extends StatefulWidget> on State<T> {
  ChatMessage? _replyingTo;
  bool _replyPings = true;

  ChatMessage? get replyingTo => _replyingTo;
  String? get replyToId => _replyingTo?.id;
  bool get replyPings => _replyPings;

  void startReply(ChatMessage message) {
    setState(() {
      _replyingTo = message;
      // Fresh per reply. Answering one message quietly is a decision about
      // that message, and carrying it forward would silence the next one
      // without saying so.
      _replyPings = true;
    });
  }

  /// Put back a reply whose message the server refused, alongside the words
  /// the composer puts back — unless another one has been started since.
  void restoreReply(ChatMessage message, {required bool pings}) {
    if (!mounted || _replyingTo != null) return;
    setState(() {
      _replyingTo = message;
      _replyPings = pings;
    });
  }

  void cancelReply() {
    if (_replyingTo == null) return;
    setState(() => _replyingTo = null);
  }

  void setReplyPing(bool on) {
    if (_replyPings == on) return;
    setState(() => _replyPings = on);
  }

  /// Called from `build` with the rows currently loaded and the conversation
  /// they belong to. Two things end a draft that nobody cancelled:
  ///
  /// - **the conversation changed.** A reply is to a message in one room, and
  ///   carrying it into the next would seal a reference that resolves to a
  ///   different message, or to nothing.
  /// - **the message went away.** Deleted, or scrolled out of the loaded
  ///   page. The send path resolves against the same list and would quietly
  ///   drop the reference, so the bar has to stop claiming otherwise.
  ///
  /// Deferred to the end of the frame: this runs during `build`, where
  /// calling `setState` is not allowed.
  void syncReplyDraft(String? conversationId, List<ChatMessage> messages) {
    final target = _replyingTo;
    if (target == null) {
      _replyConversation = conversationId;
      return;
    }
    final stale =
        conversationId != _replyConversation ||
        !messages.any((m) => m.id == target.id);
    _replyConversation = conversationId;
    if (!stale) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) cancelReply();
    });
  }

  String? _replyConversation;
}
