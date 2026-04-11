import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orbital/data/database/tables.dart';
import 'package:orbital/ssh/ssh_credential.dart';
import 'package:orbital/ssh/ssh_key_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final keyService = SshKeyService();

  String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

  group('SshCredential storage', () {
    test('round-trips password credentials through storage', () {
      const credential = PasswordCredential(password: 'secret');

      final decoded = SshCredential.decodeForStorage(
        credential.encodeForStorage(),
        AuthType.password,
      );

      expect(decoded, isA<PasswordCredential>());
      expect((decoded as PasswordCredential).password, 'secret');
    });

    test('round-trips private key credentials through storage', () {
      final credential = keyService.analyzePrivateKey(
        fixture('id_ed25519'),
        source: PrivateKeySource.file,
      );

      final decoded = SshCredential.decodeForStorage(
        credential.encodeForStorage(),
        AuthType.privateKey,
      );

      expect(decoded, isA<PrivateKeyCredential>());
      final privateKey = decoded as PrivateKeyCredential;
      expect(privateKey.source, PrivateKeySource.file);
      expect(privateKey.publicKey, isNotEmpty);
      expect(privateKey.fingerprint, startsWith('SHA256:'));
    });

    test('falls back to legacy raw password storage', () {
      final decoded = SshCredential.decodeForStorage(
        'legacy-password',
        AuthType.password,
      );

      expect(decoded, isA<PasswordCredential>());
      expect((decoded as PasswordCredential).password, 'legacy-password');
    });

    test('falls back to legacy raw private key storage', () {
      final pem = fixture('id_ed25519');

      final decoded = SshCredential.decodeForStorage(pem, AuthType.privateKey);

      expect(decoded, isA<PrivateKeyCredential>());
      expect((decoded as PrivateKeyCredential).pem, pem);
      expect(decoded.source, PrivateKeySource.manual);
    });
  });

  group('SshKeyService', () {
    test('analyzes unencrypted private keys', () {
      final credential = keyService.analyzePrivateKey(
        fixture('id_ed25519'),
        source: PrivateKeySource.clipboard,
      );

      expect(credential.publicKey, startsWith('ssh-ed25519 '));
      expect(credential.fingerprint, startsWith('SHA256:'));
      expect(credential.source, PrivateKeySource.clipboard);
      expect(keyService.resolveCredential(credential).identities, isNotEmpty);
    });

    test('requires a passphrase for encrypted private keys', () {
      expect(
        () => keyService.analyzePrivateKey(
          fixture('id_ed25519_encrypted'),
          source: PrivateKeySource.file,
        ),
        throwsA(
          isA<SshKeyValidationException>().having(
            (error) => error.message,
            'message',
            contains('passphrase'),
          ),
        ),
      );
    });

    test('accepts encrypted private keys with the correct passphrase', () {
      final credential = keyService.analyzePrivateKey(
        fixture('id_ed25519_encrypted'),
        source: PrivateKeySource.file,
        passphrase: fixture('id_ed25519_encrypted_passphrase').trim(),
      );

      expect(credential.hasPassphrase, isTrue);
      expect(credential.publicKey, startsWith('ssh-ed25519 '));
      expect(keyService.resolveCredential(credential).identities, isNotEmpty);
    });

    test('rejects encrypted private keys with the wrong passphrase', () {
      expect(
        () => keyService.analyzePrivateKey(
          fixture('id_ed25519_encrypted'),
          source: PrivateKeySource.file,
          passphrase: 'wrong-passphrase',
        ),
        throwsA(
          isA<SshKeyValidationException>().having(
            (error) => error.message,
            'message',
            contains('Incorrect'),
          ),
        ),
      );
    });

    test('generates Ed25519 keypairs', () async {
      final credential = await keyService.generateKey(
        algorithm: GeneratedKeyAlgorithm.ed25519,
      );

      expect(credential.source, PrivateKeySource.generated);
      expect(credential.algorithm, GeneratedKeyAlgorithm.ed25519);
      expect(credential.publicKey, startsWith('ssh-ed25519 '));
      expect(credential.fingerprint, startsWith('SHA256:'));
    });

    test('generates RSA 4096 keypairs', () async {
      final credential = await keyService.generateKey(
        algorithm: GeneratedKeyAlgorithm.rsa4096,
      );

      expect(credential.source, PrivateKeySource.generated);
      expect(credential.algorithm, GeneratedKeyAlgorithm.rsa4096);
      expect(credential.publicKey, startsWith('ssh-rsa '));
      expect(credential.fingerprint, startsWith('SHA256:'));
    });
  });
}
