/// Snapshot of a server's current metrics fetched via SSH
class ServerMetrics {
  final DateTime fetchedAt;

  // CPU
  final double cpuUsagePercent;
  final List<double> cpuCoreUsages;
  final double loadAvg1;
  final double loadAvg5;
  final double loadAvg15;

  // Memory
  final int memTotalKb;
  final int memAvailableKb;
  final int memUsedKb;
  final int swapTotalKb;
  final int swapUsedKb;

  // Disk (primary mount)
  final int diskTotalBytes;
  final int diskUsedBytes;
  final int diskAvailBytes;

  // Network (cumulative bytes since boot)
  final int netRxBytes;
  final int netTxBytes;
  final int netRxBytesPerSec;
  final int netTxBytesPerSec;

  // System
  final int uptimeSeconds;
  final String? kernelVersion;
  final String? hostname;
  final int processCount;

  // Temperature (optional, hardware dependent)
  final double? cpuTempCelsius;

  const ServerMetrics({
    required this.fetchedAt,
    required this.cpuUsagePercent,
    required this.cpuCoreUsages,
    required this.loadAvg1,
    required this.loadAvg5,
    required this.loadAvg15,
    required this.memTotalKb,
    required this.memAvailableKb,
    required this.memUsedKb,
    required this.swapTotalKb,
    required this.swapUsedKb,
    required this.diskTotalBytes,
    required this.diskUsedBytes,
    required this.diskAvailBytes,
    required this.netRxBytes,
    required this.netTxBytes,
    required this.netRxBytesPerSec,
    required this.netTxBytesPerSec,
    required this.uptimeSeconds,
    this.kernelVersion,
    this.hostname,
    required this.processCount,
    this.cpuTempCelsius,
  });

  double get memUsagePercent =>
      memTotalKb > 0 ? (memUsedKb / memTotalKb) * 100 : 0;

  double get diskUsagePercent =>
      diskTotalBytes > 0 ? (diskUsedBytes / diskTotalBytes) * 100 : 0;

  double get swapUsagePercent =>
      swapTotalKb > 0 ? (swapUsedKb / swapTotalKb) * 100 : 0;

  String get uptimeFormatted {
    final d = Duration(seconds: uptimeSeconds);
    if (d.inDays > 0) return '${d.inDays}d ${d.inHours.remainder(24)}h';
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    return '${d.inMinutes}m';
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }

  static String formatKb(int kb) => formatBytes(kb * 1024);
}

// ── ConnectionStatus ──────────────────────────────────────────────────────────

enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  error,

  /// Connected but the remote OS doesn't support the metrics script.
  /// Terminal and Docker still work; gauges are hidden.
  unsupportedPlatform,
}

// ── ServerConnectionState ─────────────────────────────────────────────────────

class ServerConnectionState {
  final ConnectionStatus status;
  final ServerMetrics? metrics;
  final String? errorMessage;
  final DateTime? connectedAt;

  /// The OS name returned by `uname -s` (e.g. "Linux", "Darwin", "FreeBSD").
  final String? osName;

  const ServerConnectionState({
    required this.status,
    this.metrics,
    this.errorMessage,
    this.connectedAt,
    this.osName,
  });

  static const disconnected = ServerConnectionState(
    status: ConnectionStatus.disconnected,
  );

  bool get isConnected =>
      status == ConnectionStatus.connected ||
      status == ConnectionStatus.unsupportedPlatform;
  bool get isConnecting => status == ConnectionStatus.connecting;
  bool get hasError => status == ConnectionStatus.error;
  bool get isUnsupportedPlatform =>
      status == ConnectionStatus.unsupportedPlatform;

  ServerConnectionState copyWith({
    ConnectionStatus? status,
    ServerMetrics? metrics,
    String? errorMessage,
    DateTime? connectedAt,
    String? osName,
  }) => ServerConnectionState(
    status: status ?? this.status,
    metrics: metrics ?? this.metrics,
    errorMessage: errorMessage ?? this.errorMessage,
    connectedAt: connectedAt ?? this.connectedAt,
    osName: osName ?? this.osName,
  );
}
