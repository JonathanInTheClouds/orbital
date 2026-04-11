import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ssh_credential.dart';
import 'ssh_key_service.dart';

const _installedMarker = '__orbital_key_installed__';
const _alreadyPresentMarker = '__orbital_key_present__';

enum SshKeyInstallStatus { installed, alreadyPresent }

enum SshKeyInstallErrorCode {
  invalidPublicKey,
  authFailed,
  connectionFailed,
  remoteCommandFailed,
  verificationFailed,
}

class SshKeyInstallException implements Exception {
  final SshKeyInstallErrorCode code;
  final String message;
  final String? stdout;
  final String? stderr;
  final int? exitCode;

  const SshKeyInstallException(
    this.code,
    this.message, {
    this.stdout,
    this.stderr,
    this.exitCode,
  });

  @override
  String toString() => message;
}

class SshKeyInstallResult {
  final SshKeyInstallStatus status;

  const SshKeyInstallResult({required this.status});

  bool get alreadyPresent => status == SshKeyInstallStatus.alreadyPresent;
}

class _SshCommandResult {
  final String stdout;
  final String stderr;
  final int? exitCode;

  const _SshCommandResult({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
  });
}

class SshKeyInstallerService {
  final SshKeyService _keyService;

  const SshKeyInstallerService(this._keyService);

  Future<SshKeyInstallResult> installPublicKey({
    required String host,
    required int port,
    required String username,
    required PasswordCredential passwordCredential,
    required PrivateKeyCredential privateKeyCredential,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final credential = _keyService.enrichPrivateKeyCredential(
      privateKeyCredential,
    );
    final publicKey = credential.publicKey;
    if (publicKey == null || publicKey.trim().isEmpty) {
      throw const SshKeyInstallException(
        SshKeyInstallErrorCode.invalidPublicKey,
        'This key does not have a public key available for installation.',
      );
    }

    SSHClient? passwordClient;
    try {
      final socket = await SSHSocket.connect(host, port, timeout: timeout);
      passwordClient = _keyService.createClient(
        socket: socket,
        username: username,
        credential: passwordCredential,
      );
      await passwordClient.authenticated;
    } on SSHAuthError catch (error) {
      passwordClient?.close();
      throw SshKeyInstallException(
        SshKeyInstallErrorCode.authFailed,
        'Password authentication failed: ${error.message}',
      );
    } on TimeoutException {
      passwordClient?.close();
      throw const SshKeyInstallException(
        SshKeyInstallErrorCode.connectionFailed,
        'Connection timed out while installing the SSH key.',
      );
    } catch (error) {
      passwordClient?.close();
      throw SshKeyInstallException(
        SshKeyInstallErrorCode.connectionFailed,
        'Failed to connect for key installation: $error',
      );
    }

    try {
      final commandResult = await _runCommand(
        passwordClient,
        buildAuthorizedKeysInstallCommand(publicKey),
      );

      if ((commandResult.exitCode ?? 1) != 0) {
        final details = commandResult.stderr.trim().isNotEmpty
            ? commandResult.stderr.trim()
            : commandResult.stdout.trim();
        throw SshKeyInstallException(
          SshKeyInstallErrorCode.remoteCommandFailed,
          details.isEmpty
              ? 'Failed to update ~/.ssh/authorized_keys on the server.'
              : 'Failed to update ~/.ssh/authorized_keys: $details',
          stdout: commandResult.stdout,
          stderr: commandResult.stderr,
          exitCode: commandResult.exitCode,
        );
      }

      final status = _parseInstallStatus(commandResult.stdout);
      await _verifyPrivateKey(
        host: host,
        port: port,
        username: username,
        credential: credential,
        timeout: timeout,
      );

      return SshKeyInstallResult(status: status);
    } finally {
      passwordClient.close();
    }
  }

  SshKeyInstallStatus _parseInstallStatus(String stdout) {
    if (stdout.contains(_alreadyPresentMarker)) {
      return SshKeyInstallStatus.alreadyPresent;
    }
    return SshKeyInstallStatus.installed;
  }

  Future<void> _verifyPrivateKey({
    required String host,
    required int port,
    required String username,
    required PrivateKeyCredential credential,
    required Duration timeout,
  }) async {
    SSHClient? keyClient;
    try {
      final socket = await SSHSocket.connect(host, port, timeout: timeout);
      keyClient = _keyService.createClient(
        socket: socket,
        username: username,
        credential: credential,
      );
      await keyClient.authenticated;
      final session = await keyClient.execute('echo ok');
      await session.done;
    } on SSHAuthError catch (error) {
      keyClient?.close();
      throw SshKeyInstallException(
        SshKeyInstallErrorCode.verificationFailed,
        'The key was uploaded, but key-based authentication failed: ${error.message}',
      );
    } on TimeoutException {
      keyClient?.close();
      throw const SshKeyInstallException(
        SshKeyInstallErrorCode.verificationFailed,
        'The key was uploaded, but verification timed out.',
      );
    } catch (error) {
      keyClient?.close();
      throw SshKeyInstallException(
        SshKeyInstallErrorCode.verificationFailed,
        'The key was uploaded, but verification failed: $error',
      );
    } finally {
      keyClient?.close();
    }
  }

  Future<_SshCommandResult> _runCommand(
    SSHClient client,
    String command,
  ) async {
    final session = await client.execute(command);
    final stdoutFuture = session.stdout.toList();
    final stderrFuture = session.stderr.toList();

    await session.done;

    final stdoutChunks = await stdoutFuture;
    final stderrChunks = await stderrFuture;
    return _SshCommandResult(
      stdout: utf8.decode(
        stdoutChunks.expand((chunk) => chunk).toList(),
        allowMalformed: true,
      ),
      stderr: utf8.decode(
        stderrChunks.expand((chunk) => chunk).toList(),
        allowMalformed: true,
      ),
      exitCode: session.exitCode,
    );
  }
}

@visibleForTesting
String buildAuthorizedKeysInstallCommand(String publicKey) {
  final escapedKey = shellSingleQuote(publicKey.trim());
  return '''
set -eu
SSH_DIR="\$HOME/.ssh"
AUTH_KEYS="\$SSH_DIR/authorized_keys"
PUBLIC_KEY=$escapedKey

mkdir -p "\$SSH_DIR"
chmod 700 "\$SSH_DIR"
touch "\$AUTH_KEYS"
chmod 600 "\$AUTH_KEYS"

if grep -Fqx -- "\$PUBLIC_KEY" "\$AUTH_KEYS"; then
  printf '%s\\n' '$_alreadyPresentMarker'
else
  if [ -s "\$AUTH_KEYS" ] && [ "\$(tail -c1 "\$AUTH_KEYS" | wc -l)" -eq 0 ]; then
    printf '\\n' >> "\$AUTH_KEYS"
  fi
  printf '%s\\n' "\$PUBLIC_KEY" >> "\$AUTH_KEYS"
  chmod 600 "\$AUTH_KEYS"
  printf '%s\\n' '$_installedMarker'
fi
''';
}

@visibleForTesting
String shellSingleQuote(String value) {
  return "'${value.replaceAll("'", "'\"'\"'")}'";
}

final sshKeyInstallerServiceProvider = Provider<SshKeyInstallerService>(
  (ref) => SshKeyInstallerService(ref.watch(sshKeyServiceProvider)),
);
