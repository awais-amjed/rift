import 'package:flutter/widgets.dart';

import '../../../../../data/classes/public_server.dart';
import '../../../../../data/classes/server.dart';

/// The public listing being edited, as one object.
///
/// Same reasoning as `ServerLimitsControllers`: these fields share all of
/// their behaviour — every one of them is seeded from the same place, read
/// back together, and means nothing on its own — and keeping them here is what
/// keeps the dialog inside its size budget.
class ListingDraft {
  final nameCtrl = TextEditingController();
  final descriptionCtrl = TextEditingController();

  List<String> tags = const [];
  bool isListed = true;

  /// A new invite code was asked for and hasn't been saved yet. Minting waits
  /// for the save because resetting locks out everyone holding the old link —
  /// backing out of the dialog must leave it working.
  bool resetLink = false;

  /// What central already holds for this server, or null when it has never
  /// been published. Also the source of the invite code a save reuses.
  PublicServer? listing;

  /// Fill the form from the existing listing, falling back to the server
  /// itself — an unpublished server starts from its own name, which is almost
  /// always the right answer and never a surprising one.
  void seed({required Server server, PublicServer? listing}) {
    this.listing = listing;
    nameCtrl.text = listing?.name ?? server.name;
    descriptionCtrl.text = listing?.description ?? '';
    tags = listing?.tags ?? const [];
    isListed = listing?.isListed ?? true;
  }

  String get name => nameCtrl.text.trim();

  /// Empty prose is no description rather than an empty one — the column is
  /// nullable and "" would be a second way to say the same thing.
  String? get description =>
      descriptionCtrl.text.trim().isEmpty ? null : descriptionCtrl.text.trim();

  void dispose() {
    nameCtrl.dispose();
    descriptionCtrl.dispose();
  }
}
