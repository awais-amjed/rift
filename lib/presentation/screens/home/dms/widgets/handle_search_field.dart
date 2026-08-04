import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/dm_conversation.dart';
import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/central_dm/central_dm_cubit.dart';
import '../../../../../logic/cubits/dm/dm_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/squircle_avatar.dart';
import '../../../../theme/app_shadows.dart';
import '../../../../theme/app_text.dart';

/// Finds people in the central directory by handle, in place.
///
/// Searching used to open a modal. That is the wrong weight for the one thing
/// this panel exists to do — you are looking for a person to talk to, not
/// filling in a form — so the field sits in the panel and drops its results
/// underneath, the way a search field anywhere else would.
class HandleSearchField extends StatefulWidget {
  const HandleSearchField({super.key});

  @override
  State<HandleSearchField> createState() => HandleSearchFieldState();
}

class HandleSearchFieldState extends State<HandleSearchField> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final LayerLink _link = LayerLink();

  Timer? _debounce;
  OverlayEntry? _overlay;
  List<DmConversation> _results = const [];
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _removeOverlay();
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      // Losing focus to a result row would tear the overlay down before the
      // tap lands, so the removal waits a frame.
      Future.delayed(const Duration(milliseconds: 120), () {
        if (mounted && !_focusNode.hasFocus) _removeOverlay();
      });
    }
    if (mounted) setState(() {});
  }

  /// Takes focus and pre-fills, for the "+" button and the member context
  /// menu. Public so the panel above can drive it.
  void focusWith(String? query) {
    if (query != null && query.isNotEmpty) {
      _controller.text = query;
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: query.length,
      );
      _search(query);
    }
    _focusNode.requestFocus();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() => _results = const []);
      _removeOverlay();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(value));
  }

  Future<void> _search(String value) async {
    if (!mounted) return;
    setState(() => _searching = true);
    _showOverlay();
    final results = await context.read<CentralDmCubit>().searchHandles(value);
    if (!mounted) return;
    setState(() {
      _results = results;
      _searching = false;
    });
    _overlay?.markNeedsBuild();
  }

  void _open(DmConversation result) {
    _controller.clear();
    _removeOverlay();
    _focusNode.unfocus();
    // Only one DM surface is open at a time.
    context.read<DmCubit>().closeConversation();
    context.read<CentralDmCubit>().openConversation(
      peerId: result.peerId,
      peerHandle: result.peerName,
      peerChatKey: result.peerChatPublicKey,
      peerSigningKey: result.peerSigningPublicKey,
    );
  }

  void _showOverlay() {
    if (_overlay != null) return;
    _overlay = OverlayEntry(builder: _buildOverlay);
    Overlay.of(context).insert(_overlay!);
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  @override
  Widget build(BuildContext context) {
    // The cubit seeds the field when you arrive from a member's context menu.
    return BlocListener<CentralDmCubit, CentralDmState>(
      listenWhen: (a, b) => a.handleQuery != b.handleQuery,
      listener: (context, state) {
        final query = state.handleQuery;
        if (query == null) return;
        focusWith(query);
        context.read<CentralDmCubit>().setHandleQuery(null);
      },
      child: BlocBuilder<ThemeCubit, ThemeState>(
        builder: (context, themeState) {
          return CompositedTransformTarget(
            link: _link,
            child: _buildField(themeState),
          );
        },
      ),
    );
  }

  Widget _buildField(ThemeState themeState) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: themeState.bgHover,
        borderRadius: BorderRadius.circular(9),
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
              onChanged: _onChanged,
              style: AppText.secondary.copyWith(
                fontSize: 12.5,
                color: themeState.textPrimary,
              ),
              cursorColor: themeState.primary,
              cursorWidth: 1.5,
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: 'Find by handle…',
                hintStyle: AppText.secondary.copyWith(
                  fontSize: 12.5,
                  color: themeState.textQuaternary,
                ),
              ),
            ),
          ),
          if (_controller.text.isNotEmpty)
            GestureDetector(
              onTap: () {
                _controller.clear();
                setState(() => _results = const []);
                _removeOverlay();
              },
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

  Widget _buildOverlay(BuildContext overlayContext) {
    final themeState = context.read<ThemeCubit>().state;
    final width = (context.findRenderObject() as RenderBox?)?.size.width ?? 240;

    return Positioned(
      width: width,
      child: CompositedTransformFollower(
        link: _link,
        // Hangs directly off the bottom of the field, so it reads as the
        // field's own results rather than a menu that happens to be nearby.
        offset: const Offset(0, 36),
        targetAnchor: Alignment.bottomLeft,
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
    if (_results.isEmpty) {
      return _message('Nobody found with that handle.', themeState);
    }
    return ListView.builder(
      padding: const EdgeInsets.all(6),
      shrinkWrap: true,
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final result = _results[index];
        return _ResultRow(
          result: result,
          themeState: themeState,
          onTap: () => _open(result),
        );
      },
    );
  }

  Widget _message(String text, ThemeState themeState) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Text(
        text,
        style: AppText.secondary.copyWith(
          fontSize: 11.5,
          color: themeState.textTertiary,
        ),
      ),
    );
  }
}

/// One person in the results drop-down.
class _ResultRow extends StatelessWidget {
  final DmConversation result;
  final ThemeState themeState;
  final VoidCallback onTap;

  const _ResultRow({
    required this.result,
    required this.themeState,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
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
              SquircleAvatar(
                name: result.peerName,
                seed: result.peerId,
                size: 26,
              ),
              Expanded(
                child: Text(
                  '@${result.peerName}',
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
