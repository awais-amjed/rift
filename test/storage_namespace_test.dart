import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/repositories/secure_storage_repository.dart';

void main() {
  group('storage namespace isolation', () {
    test('defaults follow the build flavor when RIFT_PROFILE is unset', () {
      expect(SecureStorageRepository.resolveSuffix(
          envProfile: null, releaseMode: true), '');
      expect(SecureStorageRepository.resolveSuffix(
          envProfile: null, releaseMode: false), 'dev');
    });

    test('an empty RIFT_PROFILE is treated as unset', () {
      expect(SecureStorageRepository.resolveSuffix(
          envProfile: '', releaseMode: true), '');
      expect(SecureStorageRepository.resolveSuffix(
          envProfile: '', releaseMode: false), 'dev');
    });

    test('RIFT_PROFILE overrides the flavor (so same-mode instances isolate)',
        () {
      expect(SecureStorageRepository.resolveSuffix(
          envProfile: 'a', releaseMode: true), 'a');
      expect(SecureStorageRepository.resolveSuffix(
          envProfile: 'b', releaseMode: true), 'b');
      // two release instances with different profiles must differ
      expect(
        SecureStorageRepository.resolveSuffix(envProfile: 'a', releaseMode: true),
        isNot(SecureStorageRepository.resolveSuffix(
            envProfile: 'b', releaseMode: true)),
      );
    });

    test('prefixForSuffix keeps the release default un-namespaced', () {
      expect(SecureStorageRepository.prefixForSuffix(''), '');
      expect(SecureStorageRepository.prefixForSuffix('dev'), 'dev.');
      expect(SecureStorageRepository.prefixForSuffix('a'), 'a.');
    });
  });
}
