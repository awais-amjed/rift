import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/enums/ducking_preference.dart';

void main() {
  test('reads Windows\' stored ducking choice', () {
    // `UserDuckingPreference`, as the Sound window's Communications tab
    // writes it. Anything else, including no value at all (which Rust reads
    // as 1), is Windows' default: lower other sounds by 80%.
    expect(DuckingPreference.fromRegistry(0), DuckingPreference.mute);
    expect(DuckingPreference.fromRegistry(1), DuckingPreference.lowerBy80);
    expect(DuckingPreference.fromRegistry(2), DuckingPreference.lowerBy50);
    expect(DuckingPreference.fromRegistry(3), DuckingPreference.off);
    expect(DuckingPreference.fromRegistry(9), DuckingPreference.lowerBy80);
  });
}
