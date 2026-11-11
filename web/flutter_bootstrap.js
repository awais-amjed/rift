{{flutter_js}}
{{flutter_build_config}}

// Flutter's own loader is told nothing of a service worker. Its default
// looks for any worker the page has and, finding Rift's (clip-sw.js, which
// streams chat videos), replaces it with Flutter's, which unregisters itself
// and reloads the page: once on every visit. Rift's worker also takes the
// place of any Flutter worker an older build left behind.
_flutter.loader.load();
