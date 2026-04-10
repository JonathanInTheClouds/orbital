import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Keys ──────────────────────────────────────────────────────────────────────

class _Keys {
  static const pollInterval = 'poll_interval_seconds';
  static const connectTimeout = 'connect_timeout_seconds';
  static const cpuAlertThreshold = 'cpu_alert_threshold';
  static const memoryAlertThreshold = 'memory_alert_threshold';
  static const diskAlertThreshold = 'disk_alert_threshold';
  static const showPreviewTools = 'show_preview_tools';
  static const themeMode = 'theme_mode';
  static const darkStyle = 'dark_style';
  static const tintColor = 'tint_color';
  static const biometricLockEnabled = 'biometric_lock_enabled';
  // Relay settings
  static const relayUrl = 'relay_url';
  static const relayAuthToken = 'relay_auth_token';
  static const relayServerIds = 'relay_server_ids';
}

// ── AppThemeMode ──────────────────────────────────────────────────────────────

enum AppThemeMode { system, light, dark }

// ── DarkStyle ─────────────────────────────────────────────────────────────────

enum DarkStyle { standard, black }

// ── AppTintColor ──────────────────────────────────────────────────────────────

enum AppTintColor {
  blue,
  purple,
  green,
  orange,
  red,
  pink,
  teal,
  indigo,
}

// ── AppSettings ───────────────────────────────────────────────────────────────

class AppSettings {
  final int pollIntervalSeconds;
  final int connectTimeoutSeconds;
  final double cpuAlertThreshold;
  final double memoryAlertThreshold;
  final double diskAlertThreshold;
  final bool showPreviewTools;
  final AppThemeMode themeMode;
  final DarkStyle darkStyle;
  final AppTintColor tintColor;
  final bool biometricLockEnabled;
  // Relay settings
  final String relayUrl;
  final String relayAuthToken;
  final List<String> relayServerIds;

  const AppSettings({
    this.pollIntervalSeconds = 5,
    this.connectTimeoutSeconds = 15,
    this.cpuAlertThreshold = 90.0,
    this.memoryAlertThreshold = 90.0,
    this.diskAlertThreshold = 85.0,
    this.showPreviewTools = false,
    this.themeMode = AppThemeMode.system,
    this.darkStyle = DarkStyle.standard,
    this.tintColor = AppTintColor.blue,
    this.biometricLockEnabled = false,
    this.relayUrl = '',
    this.relayAuthToken = '',
    this.relayServerIds = const [],
  });

  AppSettings copyWith({
    int? pollIntervalSeconds,
    int? connectTimeoutSeconds,
    double? cpuAlertThreshold,
    double? memoryAlertThreshold,
    double? diskAlertThreshold,
    bool? showPreviewTools,
    AppThemeMode? themeMode,
    DarkStyle? darkStyle,
    AppTintColor? tintColor,
    bool? biometricLockEnabled,
    String? relayUrl,
    String? relayAuthToken,
    List<String>? relayServerIds,
  }) =>
      AppSettings(
        pollIntervalSeconds: pollIntervalSeconds ?? this.pollIntervalSeconds,
        connectTimeoutSeconds:
            connectTimeoutSeconds ?? this.connectTimeoutSeconds,
        cpuAlertThreshold: cpuAlertThreshold ?? this.cpuAlertThreshold,
        memoryAlertThreshold: memoryAlertThreshold ?? this.memoryAlertThreshold,
        diskAlertThreshold: diskAlertThreshold ?? this.diskAlertThreshold,
        showPreviewTools: showPreviewTools ?? this.showPreviewTools,
        themeMode: themeMode ?? this.themeMode,
        darkStyle: darkStyle ?? this.darkStyle,
        tintColor: tintColor ?? this.tintColor,
        biometricLockEnabled:
            biometricLockEnabled ?? this.biometricLockEnabled,
        relayUrl: relayUrl ?? this.relayUrl,
        relayAuthToken: relayAuthToken ?? this.relayAuthToken,
        relayServerIds: relayServerIds ?? this.relayServerIds,
      );
}

// ── SettingsRepository ────────────────────────────────────────────────────────

class SettingsRepository {
  final SharedPreferences _prefs;

  const SettingsRepository(this._prefs);

  AppSettings load() => AppSettings(
        pollIntervalSeconds: _prefs.getInt(_Keys.pollInterval) ?? 5,
        connectTimeoutSeconds: _prefs.getInt(_Keys.connectTimeout) ?? 15,
        cpuAlertThreshold:
            _prefs.getDouble(_Keys.cpuAlertThreshold) ?? 90.0,
        memoryAlertThreshold:
            _prefs.getDouble(_Keys.memoryAlertThreshold) ?? 90.0,
        diskAlertThreshold:
            _prefs.getDouble(_Keys.diskAlertThreshold) ?? 85.0,
        showPreviewTools:
            _prefs.getBool(_Keys.showPreviewTools) ?? false,
        themeMode: AppThemeMode.values[_prefs.getInt(_Keys.themeMode) ?? 0],
        darkStyle: DarkStyle.values[_prefs.getInt(_Keys.darkStyle) ?? 0],
        tintColor:
            AppTintColor.values[_prefs.getInt(_Keys.tintColor) ?? 0],
        biometricLockEnabled:
            _prefs.getBool(_Keys.biometricLockEnabled) ?? false,
        relayUrl: _prefs.getString(_Keys.relayUrl) ?? '',
        relayAuthToken: _prefs.getString(_Keys.relayAuthToken) ?? '',
        relayServerIds:
            _prefs.getStringList(_Keys.relayServerIds) ?? [],
      );

  Future<void> setPollInterval(int v) =>
      _prefs.setInt(_Keys.pollInterval, v);

  Future<void> setConnectTimeout(int v) =>
      _prefs.setInt(_Keys.connectTimeout, v);

  Future<void> setCpuAlertThreshold(double v) =>
      _prefs.setDouble(_Keys.cpuAlertThreshold, v);

  Future<void> setMemoryAlertThreshold(double v) =>
      _prefs.setDouble(_Keys.memoryAlertThreshold, v);

  Future<void> setDiskAlertThreshold(double v) =>
      _prefs.setDouble(_Keys.diskAlertThreshold, v);

  Future<void> setShowPreviewTools(bool v) =>
      _prefs.setBool(_Keys.showPreviewTools, v);

  Future<void> setThemeMode(AppThemeMode v) =>
      _prefs.setInt(_Keys.themeMode, v.index);

  Future<void> setDarkStyle(DarkStyle v) =>
      _prefs.setInt(_Keys.darkStyle, v.index);

  Future<void> setTintColor(AppTintColor v) =>
      _prefs.setInt(_Keys.tintColor, v.index);

  Future<void> setBiometricLockEnabled(bool v) =>
      _prefs.setBool(_Keys.biometricLockEnabled, v);

  Future<void> setRelayUrl(String v) =>
      _prefs.setString(_Keys.relayUrl, v);

  Future<void> setRelayAuthToken(String v) =>
      _prefs.setString(_Keys.relayAuthToken, v);

  Future<void> setRelayServerIds(List<String> v) =>
      _prefs.setStringList(_Keys.relayServerIds, v);

  Future<void> resetAll() => Future.wait([
        _prefs.remove(_Keys.pollInterval),
        _prefs.remove(_Keys.connectTimeout),
        _prefs.remove(_Keys.cpuAlertThreshold),
        _prefs.remove(_Keys.memoryAlertThreshold),
        _prefs.remove(_Keys.diskAlertThreshold),
        _prefs.remove(_Keys.showPreviewTools),
        _prefs.remove(_Keys.themeMode),
        _prefs.remove(_Keys.darkStyle),
        _prefs.remove(_Keys.tintColor),
        _prefs.remove(_Keys.biometricLockEnabled),
        _prefs.remove(_Keys.relayUrl),
        _prefs.remove(_Keys.relayAuthToken),
        _prefs.remove(_Keys.relayServerIds),
      ]);
}

// ── Providers ─────────────────────────────────────────────────────────────────

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('Override in ProviderScope');
});

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository(ref.watch(sharedPreferencesProvider));
});

// ── SettingsNotifier ──────────────────────────────────────────────────────────

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.watch(settingsRepositoryProvider).load();

  SettingsRepository get _repo => ref.read(settingsRepositoryProvider);

  Future<void> setPollInterval(int v) async {
    await _repo.setPollInterval(v);
    state = state.copyWith(pollIntervalSeconds: v);
  }

  Future<void> setConnectTimeout(int v) async {
    await _repo.setConnectTimeout(v);
    state = state.copyWith(connectTimeoutSeconds: v);
  }

  Future<void> setCpuAlertThreshold(double v) async {
    await _repo.setCpuAlertThreshold(v);
    state = state.copyWith(cpuAlertThreshold: v);
  }

  Future<void> setMemoryAlertThreshold(double v) async {
    await _repo.setMemoryAlertThreshold(v);
    state = state.copyWith(memoryAlertThreshold: v);
  }

  Future<void> setDiskAlertThreshold(double v) async {
    await _repo.setDiskAlertThreshold(v);
    state = state.copyWith(diskAlertThreshold: v);
  }

  Future<void> setShowPreviewTools(bool v) async {
    await _repo.setShowPreviewTools(v);
    state = state.copyWith(showPreviewTools: v);
  }

  Future<void> setThemeMode(AppThemeMode v) async {
    await _repo.setThemeMode(v);
    state = state.copyWith(themeMode: v);
  }

  Future<void> setDarkStyle(DarkStyle v) async {
    await _repo.setDarkStyle(v);
    state = state.copyWith(darkStyle: v);
  }

  Future<void> setTintColor(AppTintColor v) async {
    await _repo.setTintColor(v);
    state = state.copyWith(tintColor: v);
  }

  Future<void> setBiometricLockEnabled(bool v) async {
    await _repo.setBiometricLockEnabled(v);
    state = state.copyWith(biometricLockEnabled: v);
  }

  Future<void> setRelayUrl(String v) async {
    await _repo.setRelayUrl(v);
    state = state.copyWith(relayUrl: v);
  }

  Future<void> setRelayAuthToken(String v) async {
    await _repo.setRelayAuthToken(v);
    state = state.copyWith(relayAuthToken: v);
  }

  Future<void> setRelayServerIds(List<String> v) async {
    await _repo.setRelayServerIds(v);
    state = state.copyWith(relayServerIds: v);
  }

  Future<void> resetAll() async {
    await _repo.resetAll();
    state = const AppSettings();
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
