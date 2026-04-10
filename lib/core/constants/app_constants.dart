class AppConstants {
  // App
  static const appName = 'Orbital';
  static const appVersion = '1.0.0';

  // SSH
  static const sshDefaultPort = 22;
  static const sshConnectTimeout = Duration(seconds: 15);
  static const sshKeepAliveInterval = Duration(seconds: 30);
  static const sshMaxRetries = 3;

  // Monitoring
  static const monitoringRefreshInterval = Duration(seconds: 5);
  static const metricHistoryMaxPoints = 60; // 5 minutes at 5s intervals
  static const metricHistoryRetentionDays = 7;

  // UI
  static const animationFast = Duration(milliseconds: 150);
  static const animationNormal = Duration(milliseconds: 250);
  static const animationSlow = Duration(milliseconds: 400);
  static const borderRadius = 16.0;
  static const borderRadiusSmall = 10.0;
  static const borderRadiusLarge = 24.0;
  static const padding = 16.0;
  static const paddingSmall = 8.0;
  static const paddingLarge = 24.0;

  // Alerts
  static const defaultCpuAlertThreshold = 90.0;
  static const defaultMemoryAlertThreshold = 90.0;
  static const defaultDiskAlertThreshold = 85.0;
  static const alertCooldownMinutes = 15;

  // Secure storage keys
  static const storageKeyPrefix = 'orbital_';
  static const credentialPrefix = '${storageKeyPrefix}cred_';

  // Database
  static const dbName = 'orbital.db';
  static const dbVersion = 3;
}

class AppRoutes {
  static const root = '/';
  static const servers = '/servers';
  static const addServer = '/servers/add';
  static const serverDetail = '/servers/:id';
  static const terminal = '/servers/:id/terminal';
  static const docker = '/servers/:id/docker';
  static const alerts = '/alerts';
  static const settings = '/settings';
}
