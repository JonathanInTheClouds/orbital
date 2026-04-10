import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/constants/app_constants.dart';
import '../database/app_database.dart';
import '../database/tables.dart';
import '../models/server_model.dart';

class ServerRepository {
  final AppDatabase _db;
  final FlutterSecureStorage _secureStorage;
  final Random _secureRandom = Random.secure();

  ServerRepository(this._db, this._secureStorage);

  // ── Servers ──────────────────────────────────────────────────────────────

  Stream<List<Server>> watchAllServers() => _db.select(_db.servers).watch();

  Future<List<Server>> getAllServers() => _db.select(_db.servers).get();

  Future<Server?> getServerById(int id) => (_db.select(
    _db.servers,
  )..where((s) => s.id.equals(id))).getSingleOrNull();

  Future<int> addServer(ServerFormData data, String credential) async {
    // Store credential securely first
    await _secureStorage.write(
      key: data.credentialStorageKey,
      value: credential,
    );
    return _db
        .into(_db.servers)
        .insert(data.toCompanion().copyWith(relayId: Value(_newUuidV4())));
  }

  Future<bool> updateServer(
    int id,
    ServerFormData data, {
    String? credential,
  }) async {
    if (credential != null) {
      await _secureStorage.write(
        key: data.credentialStorageKey,
        value: credential,
      );
    }
    return _db
        .update(_db.servers)
        .replace(data.toCompanion().copyWith(id: Value(id)));
  }

  Future<void> deleteServer(int id) async {
    final server = await getServerById(id);
    if (server != null) {
      // Clean up stored credential
      await _secureStorage.delete(key: server.credentialStorageKey);
    }
    await (_db.delete(_db.servers)..where((s) => s.id.equals(id))).go();
  }

  Future<void> updateLastConnected(int id) async {
    await (_db.update(_db.servers)..where((s) => s.id.equals(id))).write(
      ServersCompanion(lastConnectedAt: Value(DateTime.now())),
    );
  }

  // ── Credentials ──────────────────────────────────────────────────────────

  Future<String?> getCredential(String storageKey) =>
      _secureStorage.read(key: storageKey);

  String generateCredentialKey(String host, String username) =>
      '${AppConstants.credentialPrefix}${username}_$host';

  String _newUuidV4() {
    final bytes = List<int>.generate(16, (_) => _secureRandom.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    String hexByte(int b) => b.toRadixString(16).padLeft(2, '0');
    final hex = bytes.map(hexByte).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
  }

  // ── Snippets ─────────────────────────────────────────────────────────────

  Stream<List<Snippet>> watchAllSnippets() => _db.select(_db.snippets).watch();

  Future<int> addSnippet({
    required String title,
    required String command,
    String? description,
  }) => _db
      .into(_db.snippets)
      .insert(
        SnippetsCompanion.insert(
          title: title,
          command: command,
          description: Value(description),
        ),
      );

  Future<void> deleteSnippet(int id) =>
      (_db.delete(_db.snippets)..where((s) => s.id.equals(id))).go();
}

// ── Providers ────────────────────────────────────────────────────────────────

final secureStorageProvider = Provider<FlutterSecureStorage>((ref) {
  return const FlutterSecureStorage(
    aOptions: AndroidOptions(
      keyCipherAlgorithm:
          KeyCipherAlgorithm.RSA_ECB_OAEPwithSHA_256andMGF1Padding,
    ),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );
});

final serverRepositoryProvider = Provider<ServerRepository>((ref) {
  return ServerRepository(
    ref.watch(databaseProvider),
    ref.watch(secureStorageProvider),
  );
});

// ── Stream providers for UI ───────────────────────────────────────────────────

final serversProvider = StreamProvider<List<Server>>((ref) {
  return ref.watch(serverRepositoryProvider).watchAllServers();
});

final snippetsProvider = StreamProvider<List<Snippet>>((ref) {
  return ref.watch(serverRepositoryProvider).watchAllSnippets();
});

final serverByIdProvider = FutureProvider.family<Server?, int>((ref, id) {
  return ref.watch(serverRepositoryProvider).getServerById(id);
});
