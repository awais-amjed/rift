import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/constants.dart';
import '../../logic/cubits/theme/theme_cubit.dart';
import '../theme/app_shadows.dart';
import '../theme/app_text.dart';
import 'tap_to_focus.dart';

/// A search field that drops its results directly underneath itself.
///
/// Picking a person is not form-filling, so neither DM tier opens a modal for
/// it: you type where the list is and the matches appear against it. The two
/// tiers differ only in what they search — a public handle directory, or the
/// members of one server — so the field, the debounce and the drop-down live
/// here and each supplies its own [onSearch] and [itemBuilder].
class SearchDropdownField<T> extends StatefulWidget {
  final String hintText;

  /// Runs on a debounce, and again when the field is focused if
  /// [openOnFocus] is set. Returning an empty list shows [emptyMessage].
  final Future<List<T>> Function(String query) onSearch;

  /// Builds one result. `dismiss` closes the drop-down and clears the field —
  /// call it when the row's action has been taken.
  final Widget Function(BuildContext context, T item, VoidCallback dismiss)
  itemBuilder;

  /// Shown in place of results once a search has come back empty.
  final String emptyMessage;

  /// Opens the drop-down on focus with whatever is typed, including nothing.
  /// For a bounded set worth browsing (a server's members); a public directory
  /// has nothing sensible to show for an empty query.
  final bool openOnFocus;

  /// Fires when the drop-down opens and closes.
  ///
  /// The results float over whatever is behind the field, so the panel below
  /// gets a say in what it shows underneath them — see `ServerDmView` for the
  /// case this exists for.
  final ValueChanged<bool>? onOpenChanged;

  /// Supply both to drive the field from outside — to pre-fill it, or to
  /// focus it from a button elsewhere. Omit and the field owns its own.
  final TextEditingController? controller;
  final FocusNode? focusNode;

  const SearchDropdownField({
    super.key,
    required this.hintText,
    required this.onSearch,
    required this.itemBuilder,
    this.emptyMessage = 'No matches.',
    this.openOnFocus = false,
    this.onOpenChanged,
    this.controller,
    this.focusNode,
  });

  @override
  State<SearchDropdownField<T>> createState() => _SearchDropdownFieldState<T>();
}

class _SearchDropdownFieldState<T> extends State<SearchDropdownField<T>> {
  late final TextEditingController _controller =
      widget.controller ?? TextEditingController();
  late final FocusNode _focusNode = widget.focusNode ?? FocusNode();
  final LayerLink _link = LayerLink();

  Timer? _debounce;
  OverlayEntry? _overlay;
  List<T> _results = const [];
  bool _searching = false;

  /// Guards against a stale request landing after a newer one.
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    // Torn down directly rather than through `_removeOverlay`: that reports
    // the close to the panel behind, and a panel rebuilding itself while this
    // field is being disposed is a setState during teardown. Nothing is left
    // to tell — the field is going with it.
    _overlay?.remove();
    _overlay = null;
    _controller.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChanged);
    if (widget.controller == null) _controller.dispose();
    if (widget.focusNode == null) _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      if (widget.openOnFocus || _controller.text.trim().isNotEmpty) {
        _search(_controller.text);
      }
    } else {
      // A tap on a result moves focus before the tap lands, so the teardown
      // waits a frame rather than pulling the row out from under the pointer.
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted && !_focusNode.hasFocus) _removeOverlay();
      });
    }
    if (mounted) setState(() {});
  }

  /// Driven by the controller rather than `onChanged`, so text set from
  /// outside (a pre-filled query) searches exactly as typing does.
  void _onTextChanged() {
    _debounce?.cancel();
    final value = _controller.text;
    if (value.trim().isEmpty && !widget.openOnFocus) {
      setState(() => _results = const []);
      _removeOverlay();
      return;
    }
    _debounce = Timer(K.searchDebounce, () => _search(value));
  }

  Future<void> _search(String value) async {
    if (!mounted) return;
    final id = ++_requestId;
    setState(() => _searching = true);
    _showOverlay();
    final results = await widget.onSearch(value);
    if (!mounted || id != _requestId) return;
    setState(() {
      _results = results;
      _searching = false;
    });
    _overlay?.markNeedsBuild();
  }

  void _dismiss() {
    _controller.clear();
    _removeOverlay();
    _focusNode.unfocus();
  }

  void _showOverlay() {
    if (_overlay != null) {
      _overlay!.markNeedsBuild();
      return;
    }
    _overlay = OverlayEntry(builder: (_) => _buildOverlay());
    Overlay.of(context).insert(_overlay!);
    widget.onOpenChanged?.call(true);
  }

  void _removeOverlay() {
    if (_overlay == null) return;
    _overlay!.remove();
    _overlay = null;
    widget.onOpenChanged?.call(false);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return CompositedTransformTarget(
          link: _link,
          child: _buildField(themeState),
        );
      },
    );
  }

  /// The whole field focuses, magnifier and padding, magnifier included — the text
  /// itself is only about half its height, and the icon reads as part of the
  /// field to everyone who is not looking at the widget tree.
  Widget _buildField(ThemeState themeState) {
    return TapToFocus(focusNode: _focusNode, child: _buildFieldBox(themeState));
  }

  Widget _buildFieldBox(ThemeState themeState) {
    return Container(
      // The shared field height: this is a field, and at its own 32 it sat
      // shorter than the rows beneath it and under a thumb's minimum.
      height: K.fieldHeight,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: themeState.bgHover,
        borderRadius: BorderRadius.circular(K.radiusRow),
        border: Border.all(
          color: _focusNode.hasFocus
              ? themeState.primary.withValues(alpha: 0.55)
              : themeState.borderPrimary,
        ),
      ),
      child: Row(
        spacing: 8,
        children: [
          Icon(
            Icons.search_rounded,
            size: 15,
            color: themeState.textQuaternary,
          ),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              style: AppText.secondary.copyWith(color: themeState.textPrimary),
              cursorColor: themeState.primary,
              cursorWidth: 1.5,
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: widget.hintText,
                hintStyle: AppText.secondary.copyWith(
                  color: themeState.textQuaternary,
                ),
              ),
            ),
          ),
          if (_controller.text.isNotEmpty)
            GestureDetector(
              onTap: _dismiss,
              child: Icon(
                Icons.close_rounded,
                size: 14,
                color: themeState.textQuaternary,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOverlay() {
    final themeState = context.read<ThemeCubit>().state;
    final width = (context.findRenderObject() as RenderBox?)?.size.width ?? 240;

    return Positioned(
      width: width,
      child: CompositedTransformFollower(
        link: _link,
        // `targetAnchor` already lands this on the field's bottom edge, so the
        // offset is only the hairline gap — not the field's height again.
        targetAnchor: Alignment.bottomLeft,
        offset: const Offset(0, 5),
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxHeight: 260),
            decoration: BoxDecoration(
              color: themeState.bgElevated,
              borderRadius: BorderRadius.circular(K.radiusCard),
              border: Border.all(color: themeState.borderElevated),
              boxShadow: AppShadows.popover,
            ),
            child: _buildResults(themeState),
          ),
        ),
      ),
    );
  }

  Widget _buildResults(ThemeState themeState) {
    if (_searching && _results.isEmpty) {
      return _message('Searching…', themeState);
    }
    if (_results.isEmpty) return _message(widget.emptyMessage, themeState);

    return ListView.builder(
      padding: const EdgeInsets.all(6),
      shrinkWrap: true,
      itemCount: _results.length,
      itemBuilder: (context, index) =>
          widget.itemBuilder(context, _results[index], _dismiss),
    );
  }

  Widget _message(String text, ThemeState themeState) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Text(
        text,
        style: AppText.secondary.copyWith(color: themeState.textTertiary),
      ),
    );
  }
}
