import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinenacl/ed25519.dart' as ed25519;
import 'package:pointycastle/api.dart' as pointy;
import 'package:pointycastle/key_generators/api.dart';
import 'package:pointycastle/key_generators/rsa_key_generator.dart';
import 'package:pointycastle/random/fortuna_random.dart';

import 'ssh_credential.dart';

class SshKeyValidationException implements Exception {
  final String message;

  const SshKeyValidationException(this.message);

  @override
  String toString() => message;
}

class PickedTextFile {
  final String name;
  final String content;

  const PickedTextFile({required this.name, required this.content});
}

class DocumentPickerService {
  static const _channel = MethodChannel('orbital/document_picker');

  Future<PickedTextFile?> pickTextFile() async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'pickTextFile',
    );
    if (result == null) return null;
    return PickedTextFile(
      name: result['name'] as String? ?? 'key',
      content: result['content'] as String? ?? '',
    );
  }
}

class SshResolvedCredential {
  final SshCredential credential;
  final String? password;
  final List<SSHKeyPair>? identities;

  const SshResolvedCredential({
    required this.credential,
    this.password,
    this.identities,
  });
}

class SshKeyService {
  const SshKeyService();

  bool isEncryptedPem(String pem) {
    try {
      return SSHKeyPair.isEncryptedPem(pem);
    } catch (_) {
      return false;
    }
  }

  PrivateKeyCredential analyzePrivateKey(
    String pem, {
    required PrivateKeySource source,
    String? passphrase,
    GeneratedKeyAlgorithm? algorithm,
  }) {
    final normalizedPem = pem.trim();
    if (normalizedPem.isEmpty) {
      throw const SshKeyValidationException('Private key is required');
    }

    final isEncrypted = _isEncryptedPemOrThrow(normalizedPem);
    if (isEncrypted && (passphrase == null || passphrase.isEmpty)) {
      throw const SshKeyValidationException(
        'This private key is encrypted. Enter its passphrase.',
      );
    }

    final identities = _parseIdentities(normalizedPem, passphrase: passphrase);
    final publicKey = _encodeAuthorizedKey(identities.first);
    final fingerprint = _fingerprint(identities.first);

    return PrivateKeyCredential(
      pem: normalizedPem,
      passphrase: _nullIfEmpty(passphrase),
      publicKey: publicKey,
      fingerprint: fingerprint,
      source: source,
      algorithm: algorithm,
    );
  }

  PrivateKeyCredential enrichPrivateKeyCredential(
    PrivateKeyCredential credential,
  ) {
    if (credential.publicKey != null && credential.fingerprint != null) {
      return credential;
    }

    return analyzePrivateKey(
      credential.pem,
      source: credential.source,
      passphrase: credential.passphrase,
      algorithm: credential.algorithm,
    );
  }

  Future<PrivateKeyCredential> generateKey({
    required GeneratedKeyAlgorithm algorithm,
    String comment = 'orbital-generated',
  }) async {
    final payload = await compute(_generatePrivateKeyPayload, {
      'algorithm': algorithm.name,
      'comment': comment,
    });

    return PrivateKeyCredential(
      pem: payload['pem'] as String,
      publicKey: payload['publicKey'] as String,
      fingerprint: payload['fingerprint'] as String,
      source: PrivateKeySource.generated,
      algorithm: algorithm,
    );
  }

  SshResolvedCredential resolveCredential(SshCredential credential) {
    return switch (credential) {
      PasswordCredential() => SshResolvedCredential(
        credential: credential,
        password: credential.password,
      ),
      PrivateKeyCredential() => SshResolvedCredential(
        credential: credential,
        identities: _parseIdentities(
          credential.pem,
          passphrase: credential.passphrase,
        ),
      ),
      _ => throw const SshKeyValidationException('Unsupported SSH credential'),
    };
  }

  SSHClient createClient({
    required SSHSocket socket,
    required String username,
    required SshCredential credential,
  }) {
    final resolved = resolveCredential(credential);
    return SSHClient(
      socket,
      username: username,
      onPasswordRequest: resolved.password == null
          ? null
          : () => resolved.password!,
      identities: resolved.identities,
    );
  }

  bool _isEncryptedPemOrThrow(String pem) {
    try {
      return SSHKeyPair.isEncryptedPem(pem);
    } on UnsupportedError catch (error) {
      throw SshKeyValidationException(_unsupportedKeyMessage(error));
    } on FormatException {
      throw const SshKeyValidationException(
        'Invalid private key format. Expected PEM or OpenSSH private key text.',
      );
    } catch (error) {
      throw SshKeyValidationException(_normalizeKeyError(error));
    }
  }

  List<SSHKeyPair> _parseIdentities(String pem, {String? passphrase}) {
    try {
      return [...SSHKeyPair.fromPem(pem, _nullIfEmpty(passphrase))];
    } on UnsupportedError catch (error) {
      throw SshKeyValidationException(_unsupportedKeyMessage(error));
    } catch (error) {
      throw SshKeyValidationException(_normalizeKeyError(error));
    }
  }

  String _unsupportedKeyMessage(UnsupportedError error) {
    final message = error.message ?? error.toString();
    if (message.contains('Unsupported key type')) {
      return 'Unsupported private key type.';
    }
    if (message.contains('Unsupported key derivation function') ||
        message.contains('Unsupported cipher')) {
      return 'This encrypted private key format is not supported.';
    }
    return 'Unsupported private key format.';
  }

  String _normalizeKeyError(Object error) {
    final message = error.toString();
    if (message.contains('Private key is encrypted') ||
        message.contains('passphrase is required')) {
      return 'This private key is encrypted. Enter its passphrase.';
    }
    if (message.contains('Invalid passphrase')) {
      return 'Incorrect private key passphrase.';
    }
    if (message.contains('Invalid private key') ||
        message.contains('Failed to decode private key') ||
        message.contains('Invalid magic') ||
        message.contains('Invalid private key format')) {
      return 'Invalid private key.';
    }
    return message;
  }
}

Map<String, String> _generatePrivateKeyPayload(Map<String, String> args) {
  final algorithm = GeneratedKeyAlgorithm.values.firstWhere(
    (value) => value.name == args['algorithm'],
  );
  final comment = args['comment'] ?? 'orbital-generated';

  final SSHKeyPair keyPair = switch (algorithm) {
    GeneratedKeyAlgorithm.ed25519 => _generateEd25519Key(comment),
    GeneratedKeyAlgorithm.rsa4096 => _generateRsaKey(comment),
  };

  final publicKey = _encodeAuthorizedKey(keyPair);
  final fingerprint = _fingerprint(keyPair);

  return {
    'pem': keyPair.toPem(),
    'publicKey': publicKey,
    'fingerprint': fingerprint,
  };
}

SSHKeyPair _generateEd25519Key(String comment) {
  final signingKey = ed25519.SigningKey.generate();
  return OpenSSHEd25519KeyPair(
    Uint8List.fromList(signingKey.verifyKey.asTypedList),
    Uint8List.fromList(signingKey.asTypedList),
    comment,
  );
}

SSHKeyPair _generateRsaKey(String comment) {
  final generator = RSAKeyGenerator();
  generator.init(
    pointy.ParametersWithRandom(
      RSAKeyGeneratorParameters(BigInt.from(65537), 4096, 64),
      _createSecureRandom(),
    ),
  );

  final pair = generator.generateKeyPair();
  final publicKey = pair.publicKey;
  final privateKey = pair.privateKey;

  return OpenSSHRsaKeyPair(
    publicKey.modulus!,
    publicKey.exponent!,
    privateKey.privateExponent!,
    privateKey.q!.modInverse(privateKey.p!),
    privateKey.p!,
    privateKey.q!,
    comment,
  );
}

FortunaRandom _createSecureRandom() {
  final secureRandom = FortunaRandom();
  final seed = Uint8List.fromList(
    List<int>.generate(32, (_) => Random.secure().nextInt(256)),
  );
  secureRandom.seed(pointy.KeyParameter(seed));
  return secureRandom;
}

String _encodeAuthorizedKey(SSHKeyPair keyPair) {
  final publicKey = keyPair.toPublicKey().encode();
  final typeLength = ByteData.sublistView(publicKey, 0, 4).getUint32(0);
  final type = utf8.decode(publicKey.sublist(4, 4 + typeLength));
  return '$type ${base64.encode(publicKey)}';
}

String _fingerprint(SSHKeyPair keyPair) {
  final digest = crypto.sha256.convert(keyPair.toPublicKey().encode());
  final encoded = base64.encode(digest.bytes).replaceAll('=', '');
  return 'SHA256:$encoded';
}

String? _nullIfEmpty(String? value) {
  if (value == null || value.isEmpty) return null;
  return value;
}

final sshKeyServiceProvider = Provider<SshKeyService>((ref) {
  return const SshKeyService();
});

final documentPickerServiceProvider = Provider<DocumentPickerService>((ref) {
  return DocumentPickerService();
});
