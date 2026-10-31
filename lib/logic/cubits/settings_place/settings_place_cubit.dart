import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../presentation/screens/settings/widgets/settings_tab.dart';

part 'settings_place_state.dart';

/// Where Settings was left, so opening it again comes back to the same tab
/// and the same point in it rather than to the top of General.
///
/// Kept while the app runs, not saved: the screen is a route, and everything
/// it holds goes when it closes. After a restart Settings opens on General.
class SettingsPlaceCubit extends Cubit<SettingsPlace> {
  SettingsPlaceCubit() : super(const SettingsPlace());

  /// Settings closing on [tab], scrolled [offset] down; [detailOpen] says
  /// whether a phone was showing the tab or the list of tabs.
  void leave(
    SettingsTab tab, {
    required double offset,
    required bool detailOpen,
  }) => emit(SettingsPlace(tab: tab, offset: offset, detailOpen: detailOpen));
}
