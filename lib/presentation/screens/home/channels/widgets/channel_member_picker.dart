import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../../../../data/classes/server_member.dart';
import '../../../../../data/constants.dart';
import '../../../../../logic/services/member_selection.dart';
import '../../../../common/app_text_field.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import 'member_pick_row.dart';

/// Who else is in a private channel.
///
/// Bots are absent by design rather than by oversight: a bot is keyed by an
/// admin's explicit grant and nothing else (BOTS.md §6), so offering one here
/// would be a second door into the same room — and `set_channel_members`
/// refuses them anyway.
///
/// The person creating the channel is not listed either. They are always in it,
/// and a checkbox that cannot be unticked is a worse way of saying so than not
/// drawing one.
///
/// **The search is the server's** (`search_members`). It used to be a local filter
/// over the whole roster, which is a filter over whoever happened to fit in the
/// first thousand rows — on a big server, typing a name that was really there
/// returned "No matches", and the fix was not a bigger fetch but asking the
/// question of the database. [onSearch] runs on a debounce, exactly as
/// `SearchDropdownField` does.
///
/// With an empty query the list shows the selection's own rows first — the people
/// already in the channel, who must stay visible and untickable even when they
/// are a thousand rows down the alphabet. While a query is being typed the list
/// is the matches alone, because a pinned row that has nothing to do with what
/// somebody is searching for is noise in the one moment they are looking hard.
///
/// **No row moves under the pointer.** Which rows are pinned is settled as the
/// picker opens and only grows ([MemberPins]): a tick or an untick changes the
/// mark and nothing else. Moving the ticked row up among the pinned ones made
/// the list jump with every click.
class ChannelMemberPicker extends StatefulWidget {
  /// Who is ticked, and the rows behind them. The picker never mutates it — it
  /// reports taps through [onToggle] and re-reads this.
  ///
  /// The rows matter: with an empty query they are shown first, so somebody
  /// ticked earlier stays visible even when they are a thousand rows down the
  /// alphabet and no longer in any page this picker has fetched.
  final MemberSelection selection;

  /// Runs on a debounce, and once when the picker is first shown. An empty
  /// query is a browse — `search_members` answers it with the first
  /// alphabetical page.
  final Future<List<ServerMember>> Function(String query) onSearch;

  /// Reports the whole member rather than their id, because the caller has to
  /// keep [MemberSelection.members] in step and the row is the only place that
  /// member is guaranteed to be in hand.
  final ValueChanged<ServerMember> onToggle;
  final bool enabled;

  const ChannelMemberPicker({
    super.key,
    required this.selection,
    required this.onSearch,
    required this.onToggle,
    this.enabled = true,
  });

  @override
  State<ChannelMemberPicker> createState() => _ChannelMemberPickerState();
}

class _ChannelMemberPickerState extends State<ChannelMemberPicker> {
  final TextEditingController _controller = TextEditingController();
  Timer? _timer;
  List<ServerMember> _results = const [];

  /// The answer to an empty query, kept while a search is typed: what the
  /// list goes back to the moment the field is cleared.
  List<ServerMember>? _browse;
  MemberPins _pins = MemberPins.empty;
  bool _searching = true;

  /// Guards a slow search landing after a newer one.
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _pins = _pins.after(widget.selection, browsed: _browse);
    unawaited(_search(''));
  }

  @override
  void didUpdateWidget(ChannelMemberPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    _pins = _pins.after(widget.selection, browsed: _browse);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _timer?.cancel();
    _timer = Timer(K.searchDebounce, () => unawaited(_search(value)));
    // The clear button and the pinned rows both depend on the text, so the
    // field's own repaint cannot wait for the request to come back.
    setState(() {});
  }

  Future<void> _search(String value) async {
    final id = ++_requestId;
    setState(() => _searching = true);
    final results = await widget.onSearch(value);
    if (!mounted || id != _requestId) return;
    setState(() {
      _results = results;
      if (value.trim().isEmpty) _browse = results;
      _searching = false;
    });
  }

  /// Pinned rows first, then the browse less what is pinned.
  List<ServerMember> get _visible {
    if (_controller.text.trim().isNotEmpty) return _results;
    return _pins.over(_browse ?? const []);
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppTextField(
          controller: _controller,
          label: 'Who can see it',
          hint: 'Search members',
          enabled: widget.enabled,
          onChanged: _onChanged,
        ),
        const SizedBox(height: 8),
        Container(
          height: 168,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: context.theme.bgSecondary,
            borderRadius: BorderRadius.circular(K.radiusRow),
            border: Border.all(color: context.theme.borderPrimary),
          ),
          // Inside the fill, so the rows' hover and keyboard-focus ink is
          // drawn on top of it rather than painted and then covered.
          child: Material(
            type: MaterialType.transparency,
            child: visible.isEmpty ? _message() : _list(visible),
          ),
        ),
      ],
    );
  }

  Widget _list(List<ServerMember> visible) => ListView.builder(
    padding: const EdgeInsets.symmetric(vertical: 4),
    itemCount: visible.length,
    itemBuilder: (context, i) => MemberPickRow(
      member: visible[i],
      checked: widget.selection.contains(visible[i].id),
      onTap: widget.enabled ? () => widget.onToggle(visible[i]) : null,
    ),
  );

  Widget _message() => Center(
    child: Text(
      _searching
          ? 'Searching…'
          : _controller.text.trim().isEmpty
          ? 'Nobody else here yet'
          : 'No matches',
      style: AppText.secondary.copyWith(color: context.theme.textTertiary),
    ),
  );
}
