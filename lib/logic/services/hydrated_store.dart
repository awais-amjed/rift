import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';

import '../helper_methods.dart';
import 'hydrated_keys.dart';

/// Opens the persisted cubits' store, in [directory] (null on the web), and
/// carries over state saved under a name from before [HydratedKeys].
///
/// The same box `HydratedStorage.build` opens — its name and file are
/// unchanged — but opened here, since hydrated_bloc offers no way to list
/// what is in it, and its storage class can only be built by its own build.
/// That build also moves a pre-Hive JSON file in, which no Rift install ever
/// had.
Future<Storage> openHydratedStore(String? directory) async {
  if (directory != null) Hive.init(directory);
  final box = await Hive.openBox<dynamic>(_boxName);
  final storage = _BoxStorage(box);
  try {
    await _recover(box, storage, directory);
  } catch (e) {
    // Losing the old settings is what happened before; failing to start
    // over it would be worse.
    HelperMethods.printDebug('[Storage] carrying over saved state: $e');
  }
  return storage;
}

const _boxName = 'hydrated_box';

Future<void> _recover(
  Box<dynamic> box,
  Storage storage,
  String? directory,
) async {
  final records = <String, Object?>{
    for (final key in box.keys)
      if (key is String) key: box.get(key),
  };
  if (HydratedKeys.all.every(records.containsKey)) return;

  var writeOrder = const <String>[];
  if (!kIsWeb && directory != null) {
    final file = File('$directory/$_boxName.hive');
    if (await file.exists()) {
      writeOrder = HydratedKeyRecovery.keysInWriteOrder(
        await file.readAsBytes(),
      );
    }
  }

  final plan = HydratedKeyRecovery.plan(records, writeOrder);
  for (final MapEntry(key: name, value: from) in plan.entries) {
    await storage.write(name, records[from]);
    HelperMethods.printDebug('[Storage] $name carried over from "$from"');
  }
}

/// hydrated_bloc's storage over an already open box, as its own
/// `HydratedStorage` is. Hive queues a box's writes itself.
class _BoxStorage implements Storage {
  final Box<dynamic> _box;

  _BoxStorage(this._box);

  @override
  dynamic read(String key) => _box.isOpen ? _box.get(key) : null;

  @override
  Future<void> write(String key, dynamic value) async {
    if (_box.isOpen) await _box.put(key, value);
  }

  @override
  Future<void> delete(String key) async {
    if (_box.isOpen) await _box.delete(key);
  }

  @override
  Future<void> clear() async {
    if (_box.isOpen) await _box.clear();
  }

  @override
  Future<void> close() async {
    if (_box.isOpen) await _box.close();
  }
}
