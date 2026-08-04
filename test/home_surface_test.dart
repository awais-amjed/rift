import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/enums/home_surface.dart';
import 'package:rift/logic/cubits/app/app_cubit.dart';

/// The centre pane's surface used to be a boolean, which allowed states with
/// no meaning (channel *and* DMs open). These pin the replacement: the two DM
/// tiers are separate things, and exactly one surface is current.
void main() {
  test('the two DM tiers are both DMs, and the server pane is not', () {
    expect(HomeSurface.centralDms.isDms, isTrue);
    expect(HomeSurface.serverDms.isDms, isTrue);
    expect(HomeSurface.server.isDms, isFalse);
  });

  test('the tiers are distinct — opening one is not opening the other', () {
    expect(HomeSurface.centralDms, isNot(HomeSurface.serverDms));
  });

  test('a fresh app opens on the server pane, not a DM surface', () {
    expect(const AppState().surface, HomeSurface.server);
  });

  test('copyWith carries the surface through unrelated changes', () {
    // The regression this guards: toggling the mic used to be able to drop a
    // field that copyWith forgot to thread through.
    const state = AppState(surface: HomeSurface.serverDms);
    expect(state.copyWith(audioEnabled: false).surface, HomeSurface.serverDms);
    expect(state.copyWith().surface, HomeSurface.serverDms);
  });

  test('switching surfaces replaces rather than accumulates', () {
    const state = AppState(surface: HomeSurface.centralDms);
    final next = state.copyWith(surface: HomeSurface.serverDms);
    expect(next.surface, HomeSurface.serverDms);
  });
}
