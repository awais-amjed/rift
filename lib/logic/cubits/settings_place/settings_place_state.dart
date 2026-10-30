part of 'settings_place_cubit.dart';

/// A tab in Settings and how far down it was scrolled.
class SettingsPlace extends Equatable {
  final SettingsTab tab;
  final double offset;

  /// On a phone, whether the tab was open in front of the list.
  final bool detailOpen;

  const SettingsPlace({
    this.tab = SettingsTab.general,
    this.offset = 0,
    this.detailOpen = false,
  });

  @override
  List<Object?> get props => [tab, offset, detailOpen];
}
