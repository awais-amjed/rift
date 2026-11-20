import 'package:flutter_test/flutter_test.dart';

import 'package:rift/src/rust/frb_generated.dart';

void main() {
  // The codegen writes the crate's library name into the bindings, and when
  // it cannot read the crate it writes 'UNKNOWN' without failing. Built that
  // way (Nov 19 2026), every desktop and phone build stopped at start, unable
  // to find UNKNOWN.dll.
  test('the bindings load the Rust library by its name', () {
    expect(RustLib.kDefaultExternalLibraryLoaderConfig.stem, 'rust_lib_rift');
  });
}
