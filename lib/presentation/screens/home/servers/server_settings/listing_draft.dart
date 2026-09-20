import 'package:flutter/widgets.dart';

import '../../../../../data/classes/directory_tags.dart';
import '../../../../../data/classes/public_server.dart';

/// The discovery third of the server settings dialog, as one object.
///
/// Same reasoning as [ServerLimitsControllers] beside it: these fields share
/// all of their behaviour — seeded from the same place, read back together,
/// meaningless on their own — and keeping them here is what lets the dialog
/// hold three sections and stay inside its size budget.
///
/// There is no name field. The listing is named by the server, one field up in
/// the same dialog: a server with two names is a server whose rename silently
/// doesn't reach the people looking for it.
class ListingDraft {
  final descriptionCtrl = TextEditingController();

  /// The tag being typed. Held here rather than inside `TagEditor` so that
  /// [tags] can include it — a tag typed and not turned into a chip is still
  /// a tag the person meant to add.
  final tagCtrl = TextEditingController();

  /// The tags already turned into chips. Read [tags] to save.
  List<String> committedTags = const [];

  bool isListed = false;

  /// A new invite code was asked for and hasn't been saved yet. Minting waits
  /// for Save because resetting locks out everyone holding the old link —
  /// cancelling the dialog must leave it working.
  bool resetLink = false;

  /// What central already holds for this server, or null when it has never
  /// been published. Also the source of the invite code a save reuses.
  PublicServer? listing;

  /// Fill from the existing listing. A server that has never been published
  /// starts unlisted with everything blank — publishing is always something
  /// somebody chose, never a default that ran.
  void seed(PublicServer? listing) {
    this.listing = listing;
    descriptionCtrl.text = listing?.description ?? '';
    committedTags = listing?.tags ?? const [];
    isListed = listing?.isListed ?? false;
    resetLink = false;
  }

  /// What to publish: the chips, plus anything still in the tag box.
  List<String> get tags => DirectoryTags.withPending(committedTags, tagCtrl.text);

  /// Empty prose is no description rather than an empty one — the column is
  /// nullable and "" would be a second way to say the same thing.
  String? get description =>
      descriptionCtrl.text.trim().isEmpty ? null : descriptionCtrl.text.trim();

  /// Whether Save has anything to send to central at all. A server that was
  /// never listed and still isn't shouldn't cost a round trip, or an error
  /// from a service the admin never asked to use.
  bool get touchesDirectory => listing != null || isListed;

  void dispose() {
    descriptionCtrl.dispose();
    tagCtrl.dispose();
  }
}
