part of 'chat_composer.dart';

/// Building the preview for the link in the field, on the sender's device.
///
/// Watches the text for the first `http(s)` link and, a beat after typing
/// stops, fetches the page and shows what it found above the bar. The
/// preview belongs to that link: a different link starts over, the link
/// going away takes the card with it, and the ✕ remembers that *this* link
/// is to go out bare, so retyping a word does not bring the card back.
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

  bool get _previewsEnabled =>
      LinkPreviewFetcher.isSupported &&
      context.read<AppCubit>().state.linkPreviewsEnabled;

  void _syncLinkPreview(String text) {
    if (!_previewsEnabled) return;
    final url = LinkDetector.firstUrl(text)?.toString();
    if (url == _previewUrl) return;
    _linkDebounce?.cancel();
    _fetchSerial++;
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
    final fetched = await LinkPreviewFetcher.fetch(Uri.parse(url));
    // Typing moved on, or the link changed, while the page was loading.
    if (!mounted || serial != _fetchSerial || _previewUrl != url) return;
    setState(() => _preview = fetched);
  }

  void _dismissPreview() => setState(() {
    _dismissedUrl = _previewUrl;
    _preview = null;
  });

  /// The preview to send with the message, and the slate wiped for the
  /// next one.
  PendingLinkPreview? _takePreview() {
    final preview = _preview;
    _linkDebounce?.cancel();
    _fetchSerial++;
    _preview = null;
    _previewUrl = null;
    _dismissedUrl = null;
    return preview;
  }

  void _disposeLinkPreview() => _linkDebounce?.cancel();
}
