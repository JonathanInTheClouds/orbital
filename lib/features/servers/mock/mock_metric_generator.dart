import 'dart:async';
import 'dart:math' as math;

import '../../../ssh/ssh_models.dart';

// ── MockMetricGenerator ───────────────────────────────────────────────────────

/// Generates a realistic-looking stream of [ServerConnectionState] for UI
/// preview / development purposes. No SSH connection is made.
///
/// Uses overlapping sine waves + small random noise to simulate organic
/// metric fluctuation. The first emission contains [preSeedCount] samples
/// worth of history baked in so the chart is immediately populated.
class MockMetricGenerator {
  MockMetricGenerator._();

  static final _rng = math.Random(42); // fixed seed → repeatable

  // ── Tunable parameters ─────────────────────────────────────────────────────

  /// How many historical samples to synthesise before the stream starts.
  static const preSeedCount = 45;

  /// Interval between live ticks once the stream is running.
  static const tickInterval = Duration(seconds: 5);

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Returns a broadcast stream that:
  ///   1. Immediately yields [ConnectionStatus.connecting]
  ///   2. After 1.2 s yields [ConnectionStatus.connected] with pre-seeded metrics
  ///   3. Continues ticking every [tickInterval] with fresh metrics
  static Stream<ServerConnectionState> stream() async* {
    yield const ServerConnectionState(status: ConnectionStatus.connecting);
    await Future.delayed(const Duration(milliseconds: 1200));

    // Pre-seed history — yield one snapshot that represents "now" so that
    // the detail screen's ref.listen bridge can pick up 45 historical points.
    //
    // We do this by yielding a single connected state; the bridge only appends
    // one sample per emission, so the chart's rolling buffer fills as ticks
    // arrive. To make the chart look alive on first open we instead emit
    // multiple states rapidly before settling into the normal cadence.
    final now = DateTime.now();
    for (var i = preSeedCount; i >= 0; i--) {
      final t = now.subtract(Duration(seconds: i * 5));
      yield ServerConnectionState(
        status: ConnectionStatus.connected,
        metrics: _generateMetrics(t, tick: preSeedCount - i),
        connectedAt: now.subtract(Duration(seconds: preSeedCount * 5)),
      );
      // Tiny delay so Riverpod doesn't batch-deduplicate the rapid emissions.
      if (i > 0) await Future.delayed(const Duration(milliseconds: 16));
    }

    // Live ticking
    var tick = preSeedCount + 1;
    await for (final _ in Stream.periodic(tickInterval)) {
      yield ServerConnectionState(
        status: ConnectionStatus.connected,
        metrics: _generateMetrics(DateTime.now(), tick: tick++),
        connectedAt: now.subtract(Duration(seconds: preSeedCount * 5)),
      );
    }
  }

  // ── Metric generation ──────────────────────────────────────────────────────

  static ServerMetrics _generateMetrics(DateTime time, {required int tick}) {
    final t = tick.toDouble();

    // CPU: base 35 %, slow wave + fast ripple + spike every ~18 ticks
    final cpuBase = 35 + 20 * math.sin(t * 0.18) + 8 * math.sin(t * 0.55);
    final cpuSpike = (tick % 18 < 3) ? 30.0 : 0.0;
    final cpu =
        (cpuBase + cpuSpike + _noise(6)).clamp(2.0, 98.0);

    // RAM: slowly climbs then drops, stays mid-range
    final mem =
        (52 + 12 * math.sin(t * 0.07) + _noise(3)).clamp(20.0, 95.0);

    // Disk: very stable, tiny drift
    final disk = (61 + _noise(0.8)).clamp(0.0, 99.0);

    // Load avg follows CPU roughly
    final load1 = (cpu / 100 * 4 + _noise(0.3)).clamp(0.0, 8.0);
    final load5 = (load1 * 0.8 + _noise(0.15)).clamp(0.0, 8.0);
    final load15 = (load5 * 0.85 + _noise(0.1)).clamp(0.0, 8.0);

    // Network: bursty — occasional download spike, low baseline upload
    final netBurst = (tick % 12 < 2) ? 1 : 0;
    final netRx = ((800 * 1024 * netBurst) +
            (120 * 1024 * math.sin(t * 0.3).abs()) +
            _noise(40 * 1024))
        .clamp(0.0, 10 * 1024 * 1024)
        .toInt();
    final netTx = ((80 * 1024 * math.sin(t * 0.2).abs()) + _noise(20 * 1024))
        .clamp(0.0, 5 * 1024 * 1024)
        .toInt();

    // Memory breakdown: 16 GB total
    const memTotalKb = 16 * 1024 * 1024;
    final memUsedKb = (memTotalKb * (mem / 100)).round();
    final memAvailKb = memTotalKb - memUsedKb;

    // Disk: 500 GB total
    const diskTotal = 500 * 1024 * 1024 * 1024;
    final diskUsed = (diskTotal * (disk / 100)).round();

    // Temperature: follows CPU loosely
    final temp = 38 + cpu * 0.35 + _noise(2);

    return ServerMetrics(
      fetchedAt: time,
      cpuUsagePercent: cpu,
      cpuCoreUsages: const [],
      loadAvg1: double.parse(load1.toStringAsFixed(2)),
      loadAvg5: double.parse(load5.toStringAsFixed(2)),
      loadAvg15: double.parse(load15.toStringAsFixed(2)),
      memTotalKb: memTotalKb,
      memAvailableKb: memAvailKb,
      memUsedKb: memUsedKb,
      swapTotalKb: 4 * 1024 * 1024,
      swapUsedKb: (200 * 1024 + _noise(50 * 1024)).abs().round(),
      diskTotalBytes: diskTotal,
      diskUsedBytes: diskUsed,
      diskAvailBytes: diskTotal - diskUsed,
      netRxBytes: 0,
      netTxBytes: 0,
      netRxBytesPerSec: netRx,
      netTxBytesPerSec: netTx,
      uptimeSeconds: 3_600 * 24 * 7 + tick * 5, // ~7 days + running time
      hostname: 'prod-web-01.example.com',
      kernelVersion: '6.8.0-51-generic',
      processCount: 187 + (tick % 5),
      cpuTempCelsius: temp.clamp(30.0, 95.0),
    );
  }

  /// Small Gaussian-ish noise via CLT approximation.
  static double _noise(double scale) =>
      (_rng.nextDouble() + _rng.nextDouble() - 1.0) * scale;
}
