import 'package:flutter/material.dart';

/// Owns the message list's [ScrollController] and asks for the next history
/// page as the user nears the oldest message.
///
/// The list is reversed, so "scrolled back to the oldest message" is the far
/// end of the scroll extent — the page is requested [_threshold] pixels before
/// it so the history is already there when they arrive. Mix into a chat view's
/// [State] and implement [loadMoreHistory] with the cubit call.
mixin ChatScrollLoadMore<T extends StatefulWidget> on State<T> {
  static const double _threshold = 200;

  final ScrollController scrollController = ScrollController();

  /// Fetch the next page — typically `context.read<SomeChatCubit>()
  /// .loadMoreHistory()`. Cubits ignore the call when there's nothing more.
  void loadMoreHistory();

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
  }
}
