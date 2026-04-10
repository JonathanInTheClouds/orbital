import 'package:flutter_test/flutter_test.dart';
import 'package:orbital/ssh/metrics_parser.dart';

void main() {
  group('MetricsParser.parse', () {
    test('parses complete metrics payload', () {
      final raw = '''
CPU_PCT=42
LOAD_1=1.23
LOAD_5=0.89
LOAD_15=0.75
PROC_COUNT=211
MEM_TOTAL=1024
MEM_AVAIL=256
SWAP_TOTAL=2048
SWAP_FREE=1536
DISK_TOTAL=100000
DISK_USED=40000
DISK_AVAIL=60000
NET_RX=1000
NET_TX=2000
NET_RX_SEC=300
NET_TX_SEC=400
UPTIME=3601
HOSTNAME=test-host
KERNEL=6.8.1
CPU_TEMP=55.4
''';

      final metrics = MetricsParser.parse(raw, null);

      expect(metrics, isNotNull);
      expect(metrics!.cpuUsagePercent, 42);
      expect(metrics.loadAvg1, 1.23);
      expect(metrics.processCount, 211);
      expect(metrics.memTotalKb, 1024);
      expect(metrics.memAvailableKb, 256);
      expect(metrics.memUsedKb, 768);
      expect(metrics.swapUsedKb, 512);
      expect(metrics.diskUsedBytes, 40000);
      expect(metrics.netRxBytesPerSec, 300);
      expect(metrics.uptimeSeconds, 3601);
      expect(metrics.hostname, 'test-host');
      expect(metrics.kernelVersion, '6.8.1');
      expect(metrics.cpuTempCelsius, 55.4);
    });

    test('falls back to safe defaults on missing values', () {
      final metrics = MetricsParser.parse('CPU_PCT=abc\nMEM_TOTAL=\n', null);

      expect(metrics, isNotNull);
      expect(metrics!.cpuUsagePercent, 0);
      expect(metrics.memTotalKb, 1);
      expect(metrics.memAvailableKb, 0);
      expect(metrics.memUsedKb, 1);
      expect(metrics.swapTotalKb, 0);
      expect(metrics.swapUsedKb, 0);
      expect(metrics.hostname, isNull);
    });

    test('parses integer from decimal-like text', () {
      final metrics = MetricsParser.parse('MEM_TOTAL=1200.9\nMEM_AVAIL=200.2', null);

      expect(metrics, isNotNull);
      expect(metrics!.memTotalKb, 1200);
      expect(metrics.memAvailableKb, 200);
      expect(metrics.memUsedKb, 1000);
    });
  });
}
