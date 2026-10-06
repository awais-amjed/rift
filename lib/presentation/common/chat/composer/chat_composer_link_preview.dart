part of 'chat_composer.dart';

/// Building the preview for the link in the field, on the sender's device.
///
/// Watches the text for the first `http(s)` link and, a beat after typing
/// stops, fetches the page and shows what it found above the bar. The
/// preview belongs to that link: a different link starts over, the link
/// going away takes the card with it, and the ✕ remembers that *this* link
/// is to go out bare, so retyping a word does not bring the card back.
///
/// A link sent before its card was ready still gets one: the send waits for
/// the fetch instead of going out bare. Typed and sent in one breath, a link
/// used to lose its preview to the 600 ms pause, and nothing could add it
/// later — the preview is sealed into the message.
///
/// Off entirely when the setting says so, or on the web, where the fetch
/// cannot be made.
mixin _ComposerLinkPreviewMixin on State<ChatComposer> {
  static const Duration _linkDelay = Duration(milliseconds: 600);

  PendingLinkPreview? _preview;
  String? _previewUrl;
  String? _dismissedUrl;
  Timer? _linkDebounce;
  int _fetchSerial = 0;

  /// The fetch for [_previewUrl] while it is under way, so a send can wait
  /// for the one already running rather than start another.
  Future<PendingLinkPreview?>? _fetching;

  bool get _previewsEnabled =>
      LinkPreviewFetcher.isSupported &&
      context.read<AppCubit>().state.linkPreviewsEnabled;

  void _syncLinkPreview(String text) {
    if (!_previewsEnabled) return;
    final url = LinkDetector.firstUrl(text)?.toString();
    if (url == _previewUrl) return;
    _linkDebounce?.cancel();
    _fetchSerial++;
    _fetching = null;
    if (url == null || url == _dismissedUrl) {
      if (_preview != null || _previewUrl != null) {
        setState(() {
          _preview = null;
          _previewUrl = null;
        });
      }
      return;
    }
    _previewUrl = url;
    _linkDebounce = Timer(_linkDelay, () => _fetchPreview(url));
  }

  Future<void> _fetchPreview(String url) async {
    final serial = ++_fetchSerial;
    final fetching = LinkPreviewFetcher.fetch(Uri.parse(url));
    _fetching = fetching;
    final fetched = await fetching;
    // Typing moved on, or the link changed, while the page was loading.
    if (!mounted || serial != _fetchSerial || _previewUrl != url) return;
    setState(() => _preview = fetched);
  }

  void _dismissPreview() => setState(() {
    _dismissedUrl = _previewUrl;
    _preview = null;
    _fetching = null;
    _fetchSerial++;
  });

  /// The preview to send with the message, and the slate wiped for the
  /// next one. Already built, it is handed over as it is; still being
  /// fetched, or still waiting out the pause, the send gets the fetch to
  /// wait for. Null when there is no link, it was dismissed, or previews are
  /// off. A fetch that fails completes with null, and the message goes out
  /// without a card.
  Future<PendingLinkPreview?>? _takePreview() {
    final url = _previewUrl;
    final Future<PendingLinkPreview?>? preview = _preview != null
        ? Future.value(_preview)
        : _fetching ??
              (url != null && _linkDebounce?.isActive == true
                  ? LinkPreviewFetcher.fetch(Uri.parse(url))
                  : null);
    _linkDebounce?.cancel();
    _fetchSerial++;
    _fetching = null;
    _preview = null;
    _previewUrl = null;
    _dismissedUrl = null;
    return preview;
  }

  void _disposeLinkPreview() => _linkDebounce?.cancel();
}
