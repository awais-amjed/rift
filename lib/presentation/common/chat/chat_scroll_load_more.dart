import 'package:flutter/material.dart';

/// Owns the message list's [ScrollController] and asks for the next history
/// page as the user nears the oldest message.
///
/// The list is reversed, so "scrolled back to the oldest message" is the far
/// end of the scroll extent — the page is requested [_threshold] pixels before
/// it so the history is already there when they arrive. Mix into a chat view's
/// `State` and implement [loadMoreHistory] with the cubit call.
mixin ChatScrollLoadMore<T extends StatefulWidget> on State<T> {
  static const double _threshold = 200;

  final ScrollController scrollController = ScrollController();

  /// Fetch the next page — typically the chat cubit's own `loadMoreHistory()`.
  /// Cubits ignore the call when there's nothing more to fetch.
  void loadMoreHistory();

  /// Fetch the page *after* the newest loaded one — only ever something to
  /// do while the list is a window into history, which is why it defaults to
  /// nothing. At the live end there is nothing newer than the newest row, so
  /// the cubits refuse the call and the bottom of the list is the bottom of
  /// the conversation.
  void loadNewerHistory() {}

  @override
  void initState() {
    super.initState();
    scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    scrollController.removeListener(_onScroll);
    scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!scrollController.hasClients) return;
    final position = scrollController.position;
    if (position.pixels >= position.maxScrollExtent - _threshold) {
      loadMoreHistory();
    }
    // The near end of a reversed list is the newest message. Zero means the
    // bottom, so this is the same threshold read from the other side.
    if (position.pixels <= _threshold) {
      loadNewerHistory();
    }
  }
}
