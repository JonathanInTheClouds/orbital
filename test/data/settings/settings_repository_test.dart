import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:orbital/data/settings/settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<(SettingsRepository, SharedPreferences)> buildRepo([
    Map<String, Object> seed = const {},
  ]) async {
    SharedPreferences.setMockInitialValues(seed);
    final prefs = await SharedPreferences.getInstance();
    return (SettingsRepository(prefs), prefs);
  }

  group('SettingsRepository', () {
    test('load returns defaults when no values are persisted', () async {
      final (repo, _) = await buildRepo();
      final settings = repo.load();

      expect(settings.pollIntervalSeconds, 5);
      expect(settings.connectTimeoutSeconds, 15);
      expect(settings.cpuAlertThreshold, 90);
      expect(settings.memoryAlertThreshold, 90);
      expect(settings.diskAlertThreshold, 85);
      expect(settings.showPreviewTools, isFalse);
      expect(settings.themeMode, AppThemeMode.system);
      expect(settings.biometricLockEnabled, isFalse);
      expect(settings.relayUrl, isEmpty);
      expect(settings.relayAuthToken, isEmpty);
      expect(settings.relayServerIds, isEmpty);
    });

    test('setters persist values and load reads them back', () async {
      final (repo, _) = await buildRepo();

      await repo.setPollInterval(8);
      await repo.setConnectTimeout(22);
      await repo.setCpuAlertThreshold(77);
      await repo.setMemoryAlertThreshold(66);
      await repo.setDiskAlertThreshold(55);
      await repo.setShowPreviewTools(true);
      await repo.setThemeMode(AppThemeMode.dark);
      await repo.setBiometricLockEnabled(true);
      await repo.setRelayUrl('https://relay.example.com');
      await repo.setRelayAuthToken('token-1');
      await repo.setRelayServerIds(['a', 'b']);

      final settings = repo.load();
      expect(settings.pollIntervalSeconds, 8);
      expect(settings.connectTimeoutSeconds, 22);
      expect(settings.cpuAlertThreshold, 77);
      expect(settings.memoryAlertThreshold, 66);
      expect(settings.diskAlertThreshold, 55);
      expect(settings.showPreviewTools, isTrue);
      expect(settings.themeMode, AppThemeMode.dark);
      expect(settings.biometricLockEnabled, isTrue);
      expect(settings.relayUrl, 'https://relay.example.com');
      expect(settings.relayAuthToken, 'token-1');
      expect(settings.relayServerIds, ['a', 'b']);
    });

    test('resetAll removes every persisted value', () async {
      final (repo, prefs) = await buildRepo();
      await repo.setPollInterval(99);
      await repo.setRelayUrl('x');
      await repo.resetAll();

      expect(prefs.getKeys(), isNot(contains('poll_interval_seconds')));
      expect(prefs.getKeys(), isNot(contains('relay_url')));
      final settings = repo.load();
      expect(settings.pollIntervalSeconds, 5);
      expect(settings.relayUrl, '');
    });
  });

  group('SettingsNotifier', () {
    test('updates state and provider-backed persistence', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(settingsProvider.notifier);
      await notifier.setThemeMode(AppThemeMode.light);
      await notifier.setBiometricLockEnabled(true);
      await notifier.setRelayServerIds(['server-1']);

      final settings = container.read(settingsProvider);
      expect(settings.themeMode, AppThemeMode.light);
      expect(settings.biometricLockEnabled, isTrue);
      expect(settings.relayServerIds, ['server-1']);

      await notifier.resetAll();
      final reset = container.read(settingsProvider);
      expect(reset.themeMode, AppThemeMode.system);
      expect(reset.relayServerIds, isEmpty);
    });
  });
}
