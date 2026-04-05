import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../classes/encrypted_seed.dart';
import '../classes/encrypted_vault.dart';

/// Repository wrapping platform-secure key/value storage.
///
/// Stores the unencrypted master seed (for daily use without password),
/// the encrypted vault blob (silently re-encrypted, key = HMAC(masterSeed)),
/// the encrypted seed blob (password-protected, for backup export),
/// and the joined servers list.
class SecureStorageRepository {
  static const _keyMasterSeed = 'master_seed';
  static const _keyEncryptedVault = 'encrypted_vault';
  static const _keyEncryptedSeed = 'encrypted_seed';
  static const _keyJoinedServers = 'joined_servers';

  final FlutterSecureStorage _storage;

  SecureStorageRepository({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  // ── Master Seed ──────────────────────────────────────────

  /// Save the base64-encoded master seed.
  Future<void> saveMasterSeed(String base64Seed) =>
      _storage.write(key: _keyMasterSeed, value: base64Seed);

  /// Read the base64-encoded master seed, or null if not set.
  Future<String?> getMasterSeed() => _storage.read(key: _keyMasterSeed);

  /// Whether a master seed has been stored (i.e. vault was created).
  Future<bool> hasVault() async =>
      await _storage.read(key: _keyMasterSeed) != null;

  // ── Encrypted Vault ──────────────────────────────────────

  /// Persist the encrypted vault blob (key = HMAC(masterSeed, "vault:v1")).
  Future<void> saveEncryptedVault(EncryptedVault vault) =>
      _storage.write(
        key: _keyEncryptedVault,
        value: jsonEncode(vault.toJson()),
      );

  /// Read the encrypted vault blob, or null if not set.
  Future<EncryptedVault?> getEncryptedVault() async {
    final raw = await _storage.read(key: _keyEncryptedVault);
    if (raw == null) return null;
    return EncryptedVault.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  // ── Encrypted Seed ────────────────────────────────────────

  /// Persist the encrypted seed blob (key = Argon2id(password, salt)).
  Future<void> saveEncryptedSeed(EncryptedSeed seed) =>
      _storage.write(
        key: _keyEncryptedSeed,
        value: jsonEncode(seed.toJson()),
      );

  /// Read the encrypted seed blob, or null if not set.
  Future<EncryptedSeed?> getEncryptedSeed() async {
    final raw = await _storage.read(key: _keyEncryptedSeed);
    if (raw == null) return null;
    return EncryptedSeed.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  // ── Joined Servers ────────────────────────────────────────

  /// Add a server to the joined servers list.
  Future<void> addJoinedServer(String host, String version) async {
    final servers = await getJoinedServers();

    // Don't add duplicates
    if (servers.any((s) => s.url == host)) return;

    servers.add((url: host, version: version));
    await _saveJoinedServers(servers);
  }

  /// Get the list of joined servers (host + version for key derivation).
  Future<List<({String url, String version})>> getJoinedServers() async {
    final raw = await _storage.read(key: _keyJoinedServers);
    if (raw == null) return [];

    final list = jsonDecode(raw) as List<dynamic>;
    return list.map((e) {
      final map = e as Map<String, dynamic>;
      return (url: map['url'] as String, version: map['version'] as String);
    }).toList();
  }

  /// Replace the entire joined servers list (used during backup import).
  Future<void> setJoinedServers(
    List<({String url, String version})> servers,
  ) => _saveJoinedServers(servers);

  /// Update the key derivation version for a server (after key rotation).
  Future<void> updateServerVersion(String host, String newVersion) async {
    final servers = await getJoinedServers();
    final updated = servers.map((s) {
      if (s.url == host) return (url: s.url, version: newVersion);
      return s;
    }).toList();
    await _saveJoinedServers(updated);
  }

  Future<void> _saveJoinedServers(
    List<({String url, String version})> servers,
  ) =>
      _storage.write(
        key: _keyJoinedServers,
        value: jsonEncode(
          servers.map((s) => {'url': s.url, 'version': s.version}).toList(),
        ),
      );

  // ── Wipe ─────────────────────────────────────────────────

  /// Delete all stored secrets (for testing / account reset).
  Future<void> deleteAll() => _storage.deleteAll();
}



