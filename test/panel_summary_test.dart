import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/panel_block.dart';
import 'package:rift/logic/services/panel_summary.dart';

/// What the live bar's folded player line takes from a panel: built from the
/// panel's own blocks, so every bot gets one without new vocabulary.
void main() {
  const channel = 'cccccccc-0000-4000-8000-000000000001';
  Panel panel(List<Map<String, Object?>> blocks) => Panel.tryParse({
    'v': 1,
    'live': true,
    'blocks': blocks,
  }, channelId: channel)!;

  final cover = {
    'type': 'image',
    'path': '$channel/cover.jpg',
    'sha256': 'n4bQgYhMfWWaL+qgxVrQFaO/TxsrC4Is0V1sFbDwCgg=',
    'width': 300,
    'height': 300,
  };

  test('the music bot\'s panel gives cover, song, artist, Pause and Skip', () {
    final summary = PanelSummary.of(
      panel([
        {'type': 'heading', 'text': 'Now playing'},
        cover,
        {
          'type': 'fields',
          'items': [
            {'label': 'Song', 'value': 'Windowlicker'},
            {'label': 'Artist', 'value': 'Aphex Twin'},
            {'label': 'Asked by', 'value': 'Lana'},
          ],
        },
        {'type': 'progress', 'value': 0.25, 'text': '0:50 / 3:20'},
        {'type': 'text', 'text': 'Up next: nothing'},
        {
          'type': 'actions',
          'items': [
            {'label': 'Pause', 'action': 'pause'},
            {'label': 'Skip', 'action': 'skip'},
            {'label': 'Stop', 'action': 'stop', 'style': 'danger'},
          ],
        },
      ]),
    );
    expect(summary.cover?.image?.path, '$channel/cover.jpg');
    expect(summary.title, 'Windowlicker');
    expect(summary.subtitle, 'Aphex Twin');
    expect(summary.buttons.map((b) => b.label), ['Pause', 'Skip']);
    expect(summary.progress, 0.25);
  });

  test('danger buttons are left out and at most two kept', () {
    final summary = PanelSummary.of(
      panel([
        {'type': 'heading', 'text': 'Queue'},
        {
          'type': 'actions',
          'items': [
            {'label': 'Clear', 'action': 'clear', 'style': 'danger'},
            {'label': 'Shuffle', 'action': 'shuffle'},
            {'label': 'Repeat', 'action': 'repeat', 'style': 'primary'},
            {'label': 'Skip', 'action': 'skip'},
          ],
        },
      ]),
    );
    expect(summary.buttons.map((b) => b.label), ['Shuffle', 'Repeat']);
  });

  test('a panel with no fields uses its heading', () {
    final summary = PanelSummary.of(
      panel([
        {'type': 'heading', 'text': 'Nothing playing'},
        {'type': 'text', 'text': 'Type /play and a song.'},
      ]),
    );
    expect(summary.title, 'Nothing playing');
    expect(summary.subtitle, isNull);
    expect(summary.cover, isNull);
    expect(summary.buttons, isEmpty);
    expect(summary.progress, isNull);
  });

  // ── The opened panel's pinned buttons ───────────────────

  List<PanelBlockType> types(Panel p) => [for (final b in p.blocks) b.type];

  test('the trailing buttons and menus are split off to stay in sight', () {
    final (body, controls) = PanelSummary.pinControls(
      panel([
        {'type': 'heading', 'text': 'Now playing'},
        {
          'type': 'actions',
          'items': [
            {'label': 'Like', 'action': 'like'},
          ],
        },
        {'type': 'text', 'text': 'Up next: nothing'},
        {
          'type': 'select',
          'action': 'loop',
          'options': [
            {'label': 'Loop off', 'value': 'off'},
            {'label': 'Loop one', 'value': 'one'},
          ],
        },
        {
          'type': 'actions',
          'items': [
            {'label': 'Pause', 'action': 'pause'},
          ],
        },
      ]),
    );
    // A row in the middle keeps its place among the words it belongs to.
    expect(types(body), [
      PanelBlockType.heading,
      PanelBlockType.actions,
      PanelBlockType.text,
    ]);
    expect(
      [for (final b in controls) b.type],
      [PanelBlockType.select, PanelBlockType.actions],
    );
    expect(body.live, isTrue);
  });

  test('a panel that ends in words pins nothing', () {
    final whole = panel([
      {
        'type': 'actions',
        'items': [
          {'label': 'Pause', 'action': 'pause'},
        ],
      },
      {'type': 'text', 'text': 'Up next: nothing'},
    ]);
    final (body, controls) = PanelSummary.pinControls(whole);
    expect(body, whole);
    expect(controls, isEmpty);
  });
}
