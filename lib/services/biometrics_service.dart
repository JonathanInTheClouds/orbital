import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import '../core/logging/orbital_logger.dart';

class BiometricsService {
  final LocalAuthentication _auth;

  BiometricsService({LocalAuthentication? auth})
    : _auth = auth ?? LocalAuthentication();

  Future<bool> isBiometricAuthAvailable() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isSupported = await _auth.isDeviceSupported();
      final enrolled = await _auth.getAvailableBiometrics();
      final available = (canCheck || isSupported) && enrolled.isNotEmpty;

      OrbitalLogger.instance.info(
        'Biometrics',
        'Availability check: available=$available, enrolled=${enrolled.length}, canCheck=$canCheck, supported=$isSupported',
      );

      return available;
    } on PlatformException catch (e) {
      OrbitalLogger.instance.warning(
        'Biometrics',
        'Availability check failed: ${e.code}',
      );
      return false;
    }
  }

  Future<bool> authenticateForUnlock() async {
    OrbitalLogger.instance.info('Biometrics', 'Authentication requested');
    try {
      final authenticated = await _auth.authenticate(
        localizedReason: 'Authenticate to unlock Orbital',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          sensitiveTransaction: false,
        ),
      );
      OrbitalLogger.instance.info(
        'Biometrics',
        authenticated ? 'Authentication succeeded' : 'Authentication failed or canceled',
      );
      return authenticated;
    } on PlatformException catch (e) {
      OrbitalLogger.instance.warning(
        'Biometrics',
        'Authentication error: ${e.code}',
      );
      return false;
    }
  }
}
