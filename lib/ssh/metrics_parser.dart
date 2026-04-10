import 'ssh_models.dart';

/// Parses the combined output of our metrics script into a ServerMetrics object
class MetricsParser {
  /// The script we run on the remote server to gather all metrics in one SSH call.
  /// Outputs a simple key=value format to avoid parsing complexity.
  /// Uses only POSIX shell builtins — no bc, no external dependencies.
  static const metricsScript = r'''
#!/bin/sh
# CPU usage (via /proc/stat) — pure shell arithmetic, no bc required
cpu1=$(cat /proc/stat | grep '^cpu ' | awk '{print $2+$3+$4+$5+$6+$7+$8, $5+$6}')
sleep 0.5
cpu2=$(cat /proc/stat | grep '^cpu ' | awk '{print $2+$3+$4+$5+$6+$7+$8, $5+$6}')
total1=$(echo $cpu1 | cut -d' ' -f1)
idle1=$(echo $cpu1 | cut -d' ' -f2)
total2=$(echo $cpu2 | cut -d' ' -f1)
idle2=$(echo $cpu2 | cut -d' ' -f2)
dtotal=$((total2 - total1))
didle=$((idle2 - idle1))
if [ $dtotal -gt 0 ]; then
  cpu_pct=$(( (dtotal - didle) * 100 / dtotal ))
else
  cpu_pct=0
fi
echo "CPU_PCT=$cpu_pct"

# Load average
loadavg=$(cat /proc/loadavg)
echo "LOAD_1=$(echo $loadavg | cut -d' ' -f1)"
echo "LOAD_5=$(echo $loadavg | cut -d' ' -f2)"
echo "LOAD_15=$(echo $loadavg | cut -d' ' -f3)"
echo "PROC_COUNT=$(echo $loadavg | cut -d'/' -f2 | cut -d' ' -f1)"

# Memory
cat /proc/meminfo | awk '
/MemTotal/    { print "MEM_TOTAL="$2 }
/MemAvailable/{ print "MEM_AVAIL="$2 }
/MemFree/     { print "MEM_FREE="$2 }
/SwapTotal/   { print "SWAP_TOTAL="$2 }
/SwapFree/    { print "SWAP_FREE="$2 }
'

# Disk (root mount)
df -B1 / | tail -1 | awk '{print "DISK_TOTAL="$2"\nDISK_USED="$3"\nDISK_AVAIL="$4}'

# Network (first non-lo interface)
iface=$(cat /proc/net/dev | grep -v 'lo\|Inter\|face' | awk '{print $1}' | sed 's/://' | head -1)
if [ ! -z "$iface" ]; then
  rx1=$(cat /proc/net/dev | grep "$iface" | awk '{print $2}')
  tx1=$(cat /proc/net/dev | grep "$iface" | awk '{print $10}')
  sleep 0.5
  rx2=$(cat /proc/net/dev | grep "$iface" | awk '{print $2}')
  tx2=$(cat /proc/net/dev | grep "$iface" | awk '{print $10}')
  echo "NET_RX=$rx2"
  echo "NET_TX=$tx2"
  echo "NET_RX_SEC=$(( (rx2 - rx1) * 2 ))"
  echo "NET_TX_SEC=$(( (tx2 - tx1) * 2 ))"
fi

# Uptime
echo "UPTIME=$(cat /proc/uptime | cut -d' ' -f1 | cut -d'.' -f1)"

# Hostname & kernel
echo "HOSTNAME=$(hostname)"
echo "KERNEL=$(uname -r)"

# CPU temp (best effort) — pure shell, no bc required
if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
  temp=$(cat /sys/class/thermal/thermal_zone0/temp)
  temp_int=$((temp / 1000))
  temp_dec=$(( (temp % 1000) / 100 ))
  echo "CPU_TEMP=${temp_int}.${temp_dec}"
fi
''';

  static ServerMetrics? parse(String raw, ServerMetrics? previous) {
    final Map<String, String> kv = {};
    for (final line in raw.split('\n')) {
      final idx = line.indexOf('=');
      if (idx == -1) continue;
      final key = line.substring(0, idx).trim();
      final val = line.substring(idx + 1).trim();
      kv[key] = val;
    }

    try {
      final memTotal = _parseInt(kv['MEM_TOTAL']) ?? 1;
      final memAvail = _parseInt(kv['MEM_AVAIL']) ?? 0;
      final memUsed = memTotal - memAvail;
      final swapTotal = _parseInt(kv['SWAP_TOTAL']) ?? 0;
      final swapFree = _parseInt(kv['SWAP_FREE']) ?? 0;

      return ServerMetrics(
        fetchedAt: DateTime.now(),
        cpuUsagePercent: _parseDouble(kv['CPU_PCT']) ?? 0,
        cpuCoreUsages: const [],
        loadAvg1: _parseDouble(kv['LOAD_1']) ?? 0,
        loadAvg5: _parseDouble(kv['LOAD_5']) ?? 0,
        loadAvg15: _parseDouble(kv['LOAD_15']) ?? 0,
        memTotalKb: memTotal,
        memAvailableKb: memAvail,
        memUsedKb: memUsed,
        swapTotalKb: swapTotal,
        swapUsedKb: swapTotal - swapFree,
        diskTotalBytes: _parseInt(kv['DISK_TOTAL']) ?? 0,
        diskUsedBytes: _parseInt(kv['DISK_USED']) ?? 0,
        diskAvailBytes: _parseInt(kv['DISK_AVAIL']) ?? 0,
        netRxBytes: _parseInt(kv['NET_RX']) ?? 0,
        netTxBytes: _parseInt(kv['NET_TX']) ?? 0,
        netRxBytesPerSec: _parseInt(kv['NET_RX_SEC']) ?? 0,
        netTxBytesPerSec: _parseInt(kv['NET_TX_SEC']) ?? 0,
        uptimeSeconds: _parseInt(kv['UPTIME']) ?? 0,
        hostname: kv['HOSTNAME'],
        kernelVersion: kv['KERNEL'],
        processCount: _parseInt(kv['PROC_COUNT']) ?? 0,
        cpuTempCelsius: _parseDouble(kv['CPU_TEMP']),
      );
    } catch (_) {
      return null;
    }
  }

  static int? _parseInt(String? s) {
    if (s == null || s.isEmpty) return null;
    return int.tryParse(s.split('.').first);
  }

  static double? _parseDouble(String? s) {
    if (s == null || s.isEmpty) return null;
    return double.tryParse(s);
  }
}
