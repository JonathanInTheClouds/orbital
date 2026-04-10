import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../ssh/ssh_models.dart';

// ── Constants ─────────────────────────────────────────────────────────────────

const kMetricHistoryMaxSamples = 60; // ~5 min at the default 5-second poll

// ── MetricSample ─────────────────────────────────────────────────────────────

/// A single point-in-time snapshot kept in the rolling history buffer.
class MetricSample {
  final DateTime timestamp;
  final double cpu;
  final double memory;
  final double disk;
  final int netRxPerSec;
  final int netTxPerSec;

  const MetricSample({
    required this.timestamp,
    required this.cpu,
    required this.memory,
    required this.disk,
    required this.netRxPerSec,
    required this.netTxPerSec,
  });

  factory MetricSample.fromMetrics(ServerMetrics m) => MetricSample(
    timestamp: m.fetchedAt,
    cpu: m.cpuUsagePercent,
    memory: m.memUsagePercent,
    disk: m.diskUsagePercent,
    netRxPerSec: m.netRxBytesPerSec,
    netTxPerSec: m.netTxBytesPerSec,
  );
}

// ── MetricHistory ─────────────────────────────────────────────────────────────

/// Immutable rolling history of metric samples for one server.
///
/// Once [_kMaxSamples] is reached, the oldest sample is evicted on each [add].
class MetricHistory {
  final List<MetricSample> samples;

  const MetricHistory({this.samples = const []});

  bool get isEmpty => samples.isEmpty;
  int get length => samples.length;

  MetricHistory add(MetricSample sample) {
    final next = [...samples, sample];
    return MetricHistory(
      samples: next.length > kMetricHistoryMaxSamples
          ? next.sublist(next.length - kMetricHistoryMaxSamples)
          : next,
    );
  }

  // ── Convenience series accessors (used directly by the chart widget) ───────

  List<double> get cpuValues => samples.map((s) => s.cpu).toList();
  List<double> get memoryValues => samples.map((s) => s.memory).toList();
  List<double> get diskValues => samples.map((s) => s.disk).toList();

  /// Network receive speed in bytes/sec.
  List<double> get netRxValues =>
      samples.map((s) => s.netRxPerSec.toDouble()).toList();

  /// Network transmit speed in bytes/sec.
  List<double> get netTxValues =>
      samples.map((s) => s.netTxPerSec.toDouble()).toList();

  /// Adaptive upper bound for the network chart — the highest observed speed
  /// across both RX and TX, clamped to a minimum of 512 KB/s so the chart
  /// never scales to zero.
  double get netMaxValue {
    if (samples.isEmpty) return 512 * 1024;
    double max = 512 * 1024;
    for (final s in samples) {
      if (s.netRxPerSec > max) max = s.netRxPerSec.toDouble();
      if (s.netTxPerSec > max) max = s.netTxPerSec.toDouble();
    }
    return max;
  }
}

// ── MetricHistoryNotifier ─────────────────────────────────────────────────────

/// Holds rolling histories for **all** servers in a single `Map<serverId, MetricHistory>`.
///
/// Using a single [Notifier] keyed by server ID avoids the [FamilyNotifier] API
/// that changed across Riverpod 3.x minor versions.
///
/// Usage from widgets:
/// ```dart
/// // Read history for one server (rebuilds only when that server's data changes)
/// final history = ref.watch(metricHistoryProvider(server.id));
///
/// // Append a new sample (called from ref.listen in ServerDetailScreen)
/// ref.read(metricHistoryNotifierProvider.notifier).addSample(server.id, sample);
/// ```
class MetricHistoryNotifier extends Notifier<Map<int, MetricHistory>> {
  @override
  Map<int, MetricHistory> build() => const {};

  void addSample(int serverId, MetricSample sample) {
    final current = state[serverId] ?? const MetricHistory();
    state = {...state, serverId: current.add(sample)};
  }

  /// Returns the current history for [serverId] without subscribing.
  MetricHistory historyFor(int serverId) =>
      state[serverId] ?? const MetricHistory();

  /// Clears history for all servers.
  void clearAll() => state = const {};

  /// Clears history for a single server.
  void clearServer(int serverId) {
    final next = Map<int, MetricHistory>.from(state);
    next.remove(serverId);
    state = next;
  }

  /// Total number of samples across all servers.
  int get totalSamples => state.values.fold(0, (sum, h) => sum + h.length);
}

// ── Providers ─────────────────────────────────────────────────────────────────

/// The backing store — holds histories for all servers.
final metricHistoryNotifierProvider =
    NotifierProvider<MetricHistoryNotifier, Map<int, MetricHistory>>(
      MetricHistoryNotifier.new,
    );

/// Per-server selector. Rebuilds only when the specific server's history changes.
///
/// Drop-in replacement for the old family call-site:
/// ```dart
/// ref.watch(metricHistoryProvider(server.id))  // → MetricHistory
/// ```
final metricHistoryProvider = Provider.family<MetricHistory, int>((
  ref,
  serverId,
) {
  return ref.watch(
    metricHistoryNotifierProvider.select(
      (map) => map[serverId] ?? const MetricHistory(),
    ),
  );
});
