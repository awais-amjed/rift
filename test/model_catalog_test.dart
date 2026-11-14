import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/model_catalog.dart';
import 'package:rift/data/repositories/model_transfer.dart';

/// The files `scripts/upload_models.sh` puts in the release, by published
/// name, mapped to where each comes from.
Map<String, String> _uploaded() {
  final script = File('scripts/upload_models.sh').readAsStringSync();
  final ort = RegExp(
    r'^ort_version=(\S+)$',
    multiLine: true,
  ).firstMatch(script)!.group(1)!;
  final list = RegExp(
    r'^models=\(\n(.*?)^\)',
    multiLine: true,
    dotAll: true,
  ).firstMatch(script)!.group(1)!;
  return {
    for (final m in RegExp(
      r'^\s*"([^=]+)=([^"]*)"',
      multiLine: true,
    ).allMatches(list))
      m.group(1)!.replaceAll(r'$ort_version', ort): m
          .group(2)!
          .replaceAll(r'$ort_version', ort),
  };
}

/// The catalog pins each file by hash, and the upload script is what puts
/// the files in the release. If the two drift, an app asks for a name the
/// release lacks, or for a hash no file there has, and the model never lands.
void main() {
  test('the release gets every file the app asks for, and nothing else', () {
    expect(
      _uploaded().keys.toSet(),
      ModelCatalog.all.map((f) => f.published).toSet(),
    );
  });

  test('each published name is different and carries its version', () {
    final names = ModelCatalog.all.map((f) => f.published).toList();
    expect(names.toSet(), hasLength(names.length));
    for (final name in names) {
      // A new version goes up under a new name, never over the old one.
      expect(name, matches(RegExp(r'\.(v\d+|\d+\.\d+\.\d+)\.')), reason: name);
    }
  });

  test('each hash is a SHA-256 in lower-case hex', () {
    for (final f in ModelCatalog.all) {
      expect(f.sha256, matches(RegExp(r'^[0-9a-f]{64}$')), reason: f.published);
      expect(f.size, greaterThan(0), reason: f.published);
    }
  });

  test('a model kept in this repository matches its pin', () async {
    final sources = _uploaded();
    var checked = 0;
    for (final f in ModelCatalog.all) {
      final source = sources[f.published]!;
      // The rest are built or fetched by the script, not kept here.
      if (source.contains(':')) continue;
      final file = File(source);
      expect(file.lengthSync(), f.size, reason: source);
      expect(await sha256Of(file), f.sha256, reason: source);
      checked++;
    }
    expect(checked, greaterThan(0));
  });
}
