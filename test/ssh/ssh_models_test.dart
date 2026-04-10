import 'package:flutter_test/flutter_test.dart';
import 'package:orbital/ssh/ssh_models.dart';

void main() {
  group('ServerMetrics helpers', () {
    final metrics = ServerMetrics(
      fetchedAt: DateTime(2026),
      cpuUsagePercent: 50,
      cpuCoreUsages: [],
      loadAvg1: 1,
      loadAvg5: 1,
      loadAvg15: 1,
      memTotalKb: 1000,
      memAvailableKb: 250,
      memUsedKb: 750,
      swapTotalKb: 200,
      swapUsedKb: 50,
      diskTotalBytes: 1000,
      diskUsedBytes: 400,
      diskAvailBytes: 600,
      netRxBytes: 0,
      netTxBytes: 0,
      netRxBytesPerSec: 0,
      netTxBytesPerSec: 0,
      uptimeSeconds: 3660,
      processCount: 10,
    );

    test('computes usage percentages', () {
      expect(metrics.memUsagePercent, 75);
      expect(metrics.diskUsagePercent, 40);
      expect(metrics.swapUsagePercent, 25);
    });

    test('formats uptime in days/hours, hours/minutes and minutes', () {
      final days = ServerMetrics(
        fetchedAt: DateTime(2026),
        cpuUsagePercent: 0,
        cpuCoreUsages: [],
        loadAvg1: 0,
        loadAvg5: 0,
        loadAvg15: 0,
        memTotalKb: 1,
        memAvailableKb: 1,
        memUsedKb: 0,
        swapTotalKb: 0,
        swapUsedKb: 0,
        diskTotalBytes: 1,
        diskUsedBytes: 0,
        diskAvailBytes: 1,
        netRxBytes: 0,
        netTxBytes: 0,
        netRxBytesPerSec: 0,
        netTxBytesPerSec: 0,
        uptimeSeconds: 90000,
        processCount: 0,
      );

      expect(days.uptimeFormatted, '1d 1h');
      expect(metrics.uptimeFormatted, '1h 1m');

      final mins = ServerMetrics(
        fetchedAt: DateTime(2026),
        cpuUsagePercent: 0,
        cpuCoreUsages: [],
        loadAvg1: 0,
        loadAvg5: 0,
        loadAvg15: 0,
        memTotalKb: 1,
        memAvailableKb: 1,
        memUsedKb: 0,
        swapTotalKb: 0,
        swapUsedKb: 0,
        diskTotalBytes: 1,
        diskUsedBytes: 0,
        diskAvailBytes: 1,
        netRxBytes: 0,
        netTxBytes: 0,
        netRxBytesPerSec: 0,
        netTxBytesPerSec: 0,
        uptimeSeconds: 59,
        processCount: 0,
      );
      expect(mins.uptimeFormatted, '0m');
    });

    test('formats bytes and kilobytes', () {
      expect(ServerMetrics.formatBytes(1), '1B');
      expect(ServerMetrics.formatBytes(2048), '2.0KB');
      expect(ServerMetrics.formatBytes(5 * 1024 * 1024), '5.0MB');
      expect(ServerMetrics.formatBytes(3 * 1024 * 1024 * 1024), '3.0GB');
      expect(ServerMetrics.formatKb(2), '2.0KB');
    });
  });

  group('ServerConnectionState flags', () {
    test('isConnected true for connected and unsupported states', () {
      const connected = ServerConnectionState(status: ConnectionStatus.connected);
      const unsupported =
          ServerConnectionState(status: ConnectionStatus.unsupportedPlatform);

      expect(connected.isConnected, isTrue);
      expect(unsupported.isConnected, isTrue);
      expect(const ServerConnectionState(status: ConnectionStatus.error).isConnected,
          isFalse);
    });

    test('copyWith preserves existing values when not overridden', () {
      final now = DateTime(2026, 1, 1);
      final base = ServerConnectionState(
        status: ConnectionStatus.error,
        errorMessage: 'boom',
        connectedAt: now,
        osName: 'Linux',
      );

      final updated = base.copyWith(status: ConnectionStatus.connected);
      expect(updated.status, ConnectionStatus.connected);
      expect(updated.errorMessage, 'boom');
      expect(updated.connectedAt, now);
      expect(updated.osName, 'Linux');
    });
  });
}
