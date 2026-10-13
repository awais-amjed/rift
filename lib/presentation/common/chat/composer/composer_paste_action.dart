import 'dart:async';

import 'package:flutter/widgets.dart';

/// Ctrl+V in the composer, taken from the field first: [takeClipboard]
/// attaches a copied picture or copied files and answers true, and otherwise
/// the field pastes text exactly as it would have.
///
/// The field's own paste reads text only, so before this a screenshot on the
/// clipboard pasted nothing and said nothing.
class ComposerPasteAction extends Action<PasteTextIntent> {
  final Future<bool> Function() takeClipboard;

  ComposerPasteAction(this.takeClipboard);

  @override
  Object? invoke(PasteTextIntent intent) {
    // Held now: the field's paste is reachable only while this call runs,
    // and the clipboard is read after it returns.
    final fieldPaste = callingAction;
    unawaited(() async {
      if (!await takeClipboard()) fieldPaste?.invoke(intent);
    }());
    return null;
  }

  @override
  bool get isActionEnabled => callingAction?.isActionEnabled ?? false;

  @override
  bool consumesKey(PasteTextIntent intent) =>
      callingAction?.consumesKey(intent) ?? false;
}
