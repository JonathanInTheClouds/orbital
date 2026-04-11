import 'package:flutter_test/flutter_test.dart';
import 'package:orbital/ssh/ssh_key_installer_service.dart';

void main() {
  group('buildAuthorizedKeysInstallCommand', () {
    test('creates an idempotent authorized_keys install script', () {
      const publicKey = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIexample orbital';

      final command = buildAuthorizedKeysInstallCommand(publicKey);

      expect(command, contains(r'mkdir -p "$SSH_DIR"'));
      expect(command, contains(r'touch "$AUTH_KEYS"'));
      expect(
        command,
        contains(r'grep -Fqx -- "$PUBLIC_KEY" "$AUTH_KEYS"'),
      );
      expect(command, contains('__orbital_key_installed__'));
      expect(command, contains('__orbital_key_present__'));
      expect(
        command,
        contains(r'''printf '%s\n' "$PUBLIC_KEY" >> "$AUTH_KEYS"'''),
      );
    });

    test('single-quote escaping is shell safe', () {
      const publicKey =
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIexample jonathan's-iphone";

      final quoted = shellSingleQuote(publicKey);

      expect(
        quoted,
        "'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIexample jonathan'\"'\"'s-iphone'",
      );
    });
  });
}
