import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/constants.dart';
import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';
import '../../emoji_text.dart';
import '../../tap_to_focus.dart';

/// The emoji picker's contents: a search row, a flat row of category icons,
/// and the grid.
///
/// Built on the emoji package's *data* rather than its widget. Its own picker
/// is a tabbed view with a sliding indicator and search hidden behind a
/// button, which is a different thing from the design's one-screen panel —
/// but its emoji set and search are the parts worth keeping.
class EmojiPickerPanel extends StatefulWidget {
  /// Fires with the chosen emoji. The panel stays open, so several can be
  /// picked in a row.
  final ValueChanged<String> onSelected;

  const EmojiPickerPanel({super.key, required this.onSelected});

  static const double width = 300;
  static const double height = 320;

  @override
  State<EmojiPickerPanel> createState() => _EmojiPickerPanelState();
}

class _EmojiPickerPanelState extends State<EmojiPickerPanel> {
  static const int _columns = 8;

  /// The categories the design's icon row stands for, in its order.
  static const Map<Category, IconData> _categoryIcons = {
    Category.SMILEYS: Icons.mood,
    Category.ANIMALS: Icons.pets,
    Category.FOODS: Icons.restaurant,
    Category.ACTIVITIES: Icons.sports_esports,
    Category.TRAVEL: Icons.flight,
    Category.OBJECTS: Icons.lightbulb_outline,
    Category.SYMBOLS: Icons.emoji_symbols,
    Category.FLAGS: Icons.flag,
  };

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final ScrollController _scrollController = ScrollController();

  List<CategoryEmoji> _set = const [];
  List<Emoji> _results = const [];
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _loadSet();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Drops emoji this platform has no glyph for, so the grid can't show
  /// tofu boxes.
  Future<void> _loadSet() async {
    final filtered = await EmojiPickerUtils().filterUnsupported(
      defaultEmojiSet,
    );
    if (mounted) setState(() => _set = filtered);
  }

  Future<void> _onSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _results = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    final results = await EmojiPickerUtils().searchEmoji(query.trim(), _set);
    if (mounted) setState(() => _results = results);
  }

  void _pick(String emoji) {
    context.read<AppCubit>().noteEmojiUsed(emoji);
    widget.onSelected(emoji);
  }

  /// Jumps the grid to a category's heading.
  ///
  /// The offset is summed rather than found via `ensureVisible`: the list is
  /// lazy, so a section further down has no context to scroll to yet. That
  /// only works because [_cellExtent] is pinned — left to its aspect ratio,
  /// each row would be a fraction taller than assumed and every category
  /// would land further off than the last.
  void _scrollTo(Category category) {
    final sections = _sections;
    final index = sections.indexWhere((s) => s.category == category);
    if (index < 0 || !_scrollController.hasClients) return;
    var offset = 0.0;
    for (var i = 0; i < index; i++) {
      offset += _sectionExtent(sections[i].emoji.length);
    }
    _scrollController.animateTo(
      offset.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: AppMotion.state,
      curve: Curves.easeOut,
    );
  }

  double _sectionExtent(int count) {
    final rows = (count / _columns).ceil();
    // Spacing sits *between* rows, so there is one less of it than rows.
    return _headingHeight + rows * _cellExtent + (rows - 1) * _cellSpacing;
  }

  static const double _headingHeight = 26;
  static const double _cellExtent = 32;
  static const double _cellSpacing = 2;

  /// The grid's sections: recents first, then the set in its own order.
  List<CategoryEmoji> get _sections {
    final recents = context.read<AppCubit>().state.recentEmojis;
    final rest = _set.where((c) => c.category != Category.RECENT).toList();
    if (recents.isEmpty) return rest;
    return [
      CategoryEmoji(
        Category.RECENT,
        recents.map((e) => Emoji(e, '')).toList(growable: false),
      ),
      ...rest,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeCubit>().state;
    // Rebuild the recents section as soon as one is picked.
    context.watch<AppCubit>();

    return SizedBox(
      width: EmojiPickerPanel.width,
      height: EmojiPickerPanel.height,
      child: Column(
        children: [
          _buildSearchRow(themeState),
          _divider(themeState),
          if (_results.isEmpty && !_searching) ...[
            _buildCategoryRow(themeState),
            _divider(themeState),
          ],
          Expanded(child: _buildBody(themeState)),
        ],
      ),
    );
  }

  Widget _divider(ThemeState themeState) =>
      Container(height: 1, color: themeState.borderElevated);

  /// The row is 20px taller than the text on it, and the magnifier is part of
  /// it — so the row takes the tap, not just the glyphs.
  Widget _buildSearchRow(ThemeState themeState) {
    return TapToFocus(
      focusNode: _searchFocus,
      child: _buildSearchRowBox(themeState),
    );
  }

  Widget _buildSearchRowBox(ThemeState themeState) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
              controller: _searchController,
              focusNode: _searchFocus,
              onChanged: _onSearch,
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
                hintText: 'Search emoji',
                hintStyle: AppText.secondary.copyWith(
                  color: themeState.textQuaternary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A flat row of category icons — no tab bar, no sliding indicator. They
  /// scroll the grid rather than swapping it, so the whole set stays one
  /// continuous list you can also just scroll through.
  Widget _buildCategoryRow(ThemeState themeState) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (final entry in _categoryIcons.entries)
            _CategoryButton(
              icon: entry.value,
              onTap: () => _scrollTo(entry.key),
            ),
        ],
      ),
    );
  }

  Widget _buildBody(ThemeState themeState) {
    if (_set.isEmpty) {
      return const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_searchController.text.trim().isNotEmpty) {
      if (_results.isEmpty) {
        return Center(
          child: Text(
            'No emoji found.',
            style: AppText.secondary.copyWith(color: themeState.textTertiary),
          ),
        );
      }
      return _buildGrid(_results);
    }

    final sections = _sections;
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      itemCount: sections.length,
      itemBuilder: (context, index) {
        final section = sections[index];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: _headingHeight,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _label(section.category),
                  style: AppText.sectionLabel.copyWith(
                    color: themeState.textTertiary,
                  ),
                ),
              ),
            ),
            _buildGrid(section.emoji, shrinkWrap: true),
          ],
        );
      },
    );
  }

  Widget _buildGrid(List<Emoji> emoji, {bool shrinkWrap = false}) {
    return GridView.builder(
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      padding: shrinkWrap
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(12, 10, 12, 12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _columns,
        // Fixed rather than derived from the aspect ratio, so [_scrollTo] can
        // do arithmetic on it.
        mainAxisExtent: _cellExtent,
        mainAxisSpacing: _cellSpacing,
        crossAxisSpacing: _cellSpacing,
      ),
      itemCount: emoji.length,
      itemBuilder: (context, index) => _EmojiCell(
        emoji: emoji[index].emoji,
        onTap: () => _pick(emoji[index].emoji),
      ),
    );
  }

  static String _label(Category category) => switch (category) {
    Category.RECENT => 'Frequently used',
    Category.SMILEYS => 'Smileys & people',
    Category.ANIMALS => 'Animals & nature',
    Category.FOODS => 'Food & drink',
    Category.ACTIVITIES => 'Activities',
    Category.TRAVEL => 'Travel & places',
    Category.OBJECTS => 'Objects',
    Category.SYMBOLS => 'Symbols',
    Category.FLAGS => 'Flags',
  };
}

class _CategoryButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CategoryButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return InkWell(
      mouseCursor: WidgetStateMouseCursor.clickable,
      borderRadius: BorderRadius.circular(K.radiusRow),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Icon(icon, size: 16, color: themeState.textQuaternary),
      ),
    );
  }
}

class _EmojiCell extends StatelessWidget {
  final String emoji;
  final VoidCallback onTap;

  const _EmojiCell({required this.emoji, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(K.radiusRow);
    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        borderRadius: radius,
        onTap: onTap,
        child: Center(
          child: Text(emoji, style: emojiRunStyle.copyWith(fontSize: 18)),
        ),
      ),
    );
  }
}
