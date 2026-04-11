import 'dart:convert';

import '../data/database/tables.dart';

enum PrivateKeySource { manual, clipboard, file, generated }

enum GeneratedKeyAlgorithm { ed25519, rsa4096 }

abstract class SshCredential {
  const SshCredential();

  String get storageKind;

  Map<String, Object?> toStorageJson();

  String encodeForStorage() => jsonEncode(toStorageJson());

  static SshCredential decodeForStorage(String raw, AuthType authType) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Credential payload is not an object');
      }

      final kind = decoded['kind'] as String?;
      switch (kind) {
        case PasswordCredential.storageKindValue:
          return PasswordCredential.fromJson(decoded);
        case PrivateKeyCredential.storageKindValue:
          return PrivateKeyCredential.fromJson(decoded);
      }
    } catch (_) {
      // Fall back to the legacy raw-string credential format.
    }

    return switch (authType) {
      AuthType.password => PasswordCredential(password: raw),
      AuthType.privateKey => PrivateKeyCredential(
        pem: raw,
        source: PrivateKeySource.manual,
      ),
    };
  }
}

class PasswordCredential extends SshCredential {
  static const storageKindValue = 'password';

  final String password;

  const PasswordCredential({required this.password});

  factory PasswordCredential.fromJson(Map<String, dynamic> json) {
    return PasswordCredential(password: json['password'] as String? ?? '');
  }

  @override
  String get storageKind => storageKindValue;

  @override
  Map<String, Object?> toStorageJson() => {
    'version': 1,
    'kind': storageKind,
    'password': password,
  };
}

class PrivateKeyCredential extends SshCredential {
  static const storageKindValue = 'private_key';

  final String pem;
  final String? passphrase;
  final String? publicKey;
  final String? fingerprint;
  final PrivateKeySource source;
  final GeneratedKeyAlgorithm? algorithm;

  const PrivateKeyCredential({
    required this.pem,
    required this.source,
    this.passphrase,
    this.publicKey,
    this.fingerprint,
    this.algorithm,
  });

  factory PrivateKeyCredential.fromJson(Map<String, dynamic> json) {
    final sourceValue = json['source'] as String?;
    final algorithmValue = json['algorithm'] as String?;
    return PrivateKeyCredential(
      pem: json['pem'] as String? ?? '',
      passphrase: _nullIfEmpty(json['passphrase'] as String?),
      publicKey: _nullIfEmpty(json['publicKey'] as String?),
      fingerprint: _nullIfEmpty(json['fingerprint'] as String?),
      source: PrivateKeySource.values.firstWhere(
        (value) => value.name == sourceValue,
        orElse: () => PrivateKeySource.manual,
      ),
      algorithm: algorithmValue == null
          ? null
          : GeneratedKeyAlgorithm.values.firstWhere(
              (value) => value.name == algorithmValue,
              orElse: () => GeneratedKeyAlgorithm.ed25519,
            ),
    );
  }

  bool get hasPassphrase => (passphrase ?? '').isNotEmpty;

  PrivateKeyCredential copyWith({
    String? pem,
    String? passphrase,
    String? publicKey,
    String? fingerprint,
    PrivateKeySource? source,
    GeneratedKeyAlgorithm? algorithm,
    bool clearPassphrase = false,
    bool clearPublicKey = false,
    bool clearFingerprint = false,
    bool clearAlgorithm = false,
  }) {
    return PrivateKeyCredential(
      pem: pem ?? this.pem,
      passphrase: clearPassphrase ? null : (passphrase ?? this.passphrase),
      publicKey: clearPublicKey ? null : (publicKey ?? this.publicKey),
      fingerprint: clearFingerprint ? null : (fingerprint ?? this.fingerprint),
      source: source ?? this.source,
      algorithm: clearAlgorithm ? null : (algorithm ?? this.algorithm),
    );
  }

  @override
  String get storageKind => storageKindValue;

  @override
  Map<String, Object?> toStorageJson() => {
    'version': 1,
    'kind': storageKind,
    'pem': pem,
    'passphrase': _nullIfEmpty(passphrase),
    'publicKey': _nullIfEmpty(publicKey),
    'fingerprint': _nullIfEmpty(fingerprint),
    'source': source.name,
    'algorithm': algorithm?.name,
  };
}

String? _nullIfEmpty(String? value) {
  if (value == null || value.isEmpty) return null;
  return value;
}
