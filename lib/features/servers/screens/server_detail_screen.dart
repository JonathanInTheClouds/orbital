import 'dart:async';

import 'agent_installer_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/models/alert_thresholds.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/database/app_database.dart';
import '../../../data/models/server_model.dart';
import '../../../data/repositories/server_repository.dart';
import '../../../data/settings/settings_repository.dart';
import '../../../services/dynamic_island_service.dart';
import '../../../ssh/ssh_connection_manager.dart';
import '../../../ssh/ssh_models.dart';
import '../providers/metric_history_provider.dart';
import '../providers/watch_server_provider.dart';
import '../widgets/metric_gauge.dart';
import '../widgets/metric_history_chart.dart';
import '../widgets/server_info_tile.dart';

// ── ServerDetailScreen ────────────────────────────────────────────────────────

class ServerDetailScreen extends ConsumerStatefulWidget {
  final String serverId;

  const ServerDetailScreen({super.key, required this.serverId});

  @override
  ConsumerState<ServerDetailScreen> createState() => _ServerDetailScreenState();
}

class _ServerDetailScreenState extends ConsumerState<ServerDetailScreen>
    with WidgetsBindingObserver {
  // 0 = CPU  |  1 = RAM  |  2 = Disk  |  3 = Network
  int _chartTab = 0;
  Server? _currentServer;
  bool _shouldReconnectOnResume = false;

  int get _id => int.parse(widget.serverId);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (_shouldReconnectOnResume && _currentServer != null) {
          _shouldReconnectOnResume = false;
          unawaited(_refreshConnectionAfterResume(_currentServer!));
        }
        return;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _shouldReconnectOnResume = true;
        return;
      case AppLifecycleState.detached:
        return;
    }
  }

  Future<void> _refreshConnectionAfterResume(Server server) async {
    await ref.read(sshManagerProvider).disconnect(server.id);
    if (!mounted) return;
    ref.invalidate(serverConnectionProvider(server));
  }

  // ── Dynamic Island watch toggle ───────────────────────────────────────────

  Future<void> _toggleWatch(Server server, ServerMetrics? metrics) async {
    final watchedId = ref.read(watchedServerIdProvider);
    final isWatching = watchedId == server.id;

    if (isWatching) {
      // Stop watching
      ref.read(watchedServerIdProvider.notifier).setWatchedId(null);
      await DynamicIslandService.stopWatching();
    } else {
      // Start watching — seed with current metrics (or zeros while connecting)
      final started = await DynamicIslandService.startWatching(
        serverName: server.displayName,
        host: server.host,
        cpu: metrics?.cpuUsagePercent ?? 0,
        ram: metrics?.memUsagePercent ?? 0,
        disk: metrics?.diskUsagePercent ?? 0,
      );
      if (started && mounted) {
        ref.read(watchedServerIdProvider.notifier).setWatchedId(server.id);
      } else if (!started && mounted) {

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Dynamic Island unavailable — requires iPhone 14 or later with iOS 16.1+.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final serverAsync = ref.watch(serverByIdProvider(_id));

    return serverAsync.when(
      loading: () => const _LoadingScaffold(),
      error: (e, _) => _ErrorScaffold(message: e.toString()),
      data: (server) {
        if (server == null) {
          return const _ErrorScaffold(message: 'Server not found.');
        }
        _currentServer = server;
        return _buildDetail(server);
      },
    );
  }

  // ── Main detail scaffold ──────────────────────────────────────────────────

  Widget _buildDetail(Server server) {
    final connectionAsync = ref.watch(serverConnectionProvider(server));
    final history = ref.watch(metricHistoryProvider(_id));
    final settings = ref.watch(settingsProvider);
    final thresholds = AlertThresholdProfile.effectiveForServer(
      server,
      AlertThresholdProfile(
        cpu: settings.cpuAlertThreshold,
        memory: settings.memoryAlertThreshold,
        disk: settings.diskAlertThreshold,
      ),
    );

    ref.listen<AsyncValue<ServerConnectionState>>(
      serverConnectionProvider(server),
      (_, next) {
        final metrics = next.asData?.value.metrics;
        if (metrics != null) {
          ref
              .read(metricHistoryNotifierProvider.notifier)
              .addSample(_id, MetricSample.fromMetrics(metrics));
        }
      },
    );

    final state = connectionAsync.asData?.value;
    final metrics = state?.metrics;
    final serverColor = server.displayColor ?? Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          _buildAppBar(server, state, serverColor),
          if (state?.hasError == true && metrics == null)
            SliverFillRemaining(
              child: _ConnectionErrorState(
                message: state!.errorMessage ?? 'Connection failed.',
                onRetry: () => ref.invalidate(serverConnectionProvider(server)),
              ),
            )
          else if (state == null || (state.isConnecting && metrics == null))
            const SliverFillRemaining(child: _ConnectingState())
          else if (state.isUnsupportedPlatform)
            SliverList(
              delegate: SliverChildListDelegate([
                _buildActionButtons(server),
                const SizedBox(height: 20),
                _UnsupportedPlatformBanner(osName: state.osName ?? 'Unknown'),
                const SizedBox(height: 32),
                _buildDeleteButton(server),
                const SizedBox(height: 48),
              ]),
            )
          else
            SliverList(
              delegate: SliverChildListDelegate([
                if (state.hasError && metrics != null)
                  _ErrorBanner(message: state.errorMessage!),

                _buildActionButtons(server),
                const SizedBox(height: 20),
                _buildGaugeGrid(metrics, history, thresholds, server),
                const SizedBox(height: 20),
                _buildHistorySection(history),
                const SizedBox(height: 20),
                _buildThresholdsSection(server, thresholds),
                const SizedBox(height: 20),
                _buildSystemInfoSection(metrics, server),
                const SizedBox(height: 20),
                _buildMemoryBreakdown(metrics),
                const SizedBox(height: 32),
                _buildDeleteButton(server),
                const SizedBox(height: 48),
              ]),
            ),
        ],
      ),
    );
  }

  // ── AppBar ────────────────────────────────────────────────────────────────

  SliverAppBar _buildAppBar(
    Server server,
    ServerConnectionState? state,
    Color serverColor,
  ) {
    return SliverAppBar(
      backgroundColor: Theme.of(context).colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      pinned: true,
      expandedHeight: 110,
      leading: IconButton(
        icon: Icon(
          Icons.arrow_back_ios_new_rounded,
          size: 20,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        onPressed: () => context.pop(),
      ),
      actions: [
        IconButton(
          icon: Icon(
            Icons.refresh_rounded,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          tooltip: 'Reconnect',
          onPressed: () => ref.invalidate(serverConnectionProvider(server)),
        ),
        const SizedBox(width: 4),
      ],
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.pin,
        titlePadding: const EdgeInsets.fromLTRB(56, 0, 56, 14),
        title: Row(
          children: [
            Expanded(
              child: Text(
                server.displayName,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            _StatusChip(state: state),
          ],
        ),
        background: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            boxShadow: Theme.of(context).brightness == Brightness.light
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          padding: const EdgeInsets.fromLTRB(56, 80, 56, 0),
          child: Text(
            state?.metrics?.hostname ?? server.connectionString,
            style: TextStyle(
              fontSize: 13,
              color:
                  Theme.of(context).textTheme.bodySmall?.color ??
                  OrbitalColors.textMuted,
              fontFamily: 'Menlo',
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  // ── Quick action buttons ──────────────────────────────────────────────────

  Widget _buildActionButtons(Server server) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          _ActionButton(
            icon: Icons.terminal_rounded,
            label: 'Terminal',
            onTap: () =>
                context.push('${AppRoutes.servers}/${server.id}/terminal'),
          ),
          const SizedBox(width: 10),
          _ActionButton(
            icon: Icons.inventory_2_rounded,
            label: 'Docker',
            onTap: () =>
                context.push('${AppRoutes.servers}/${server.id}/docker'),
          ),
          const SizedBox(width: 10),
          _ActionButton(
            icon: Icons.sensors_rounded,
            label: 'Agent',
            onTap: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => AgentInstallerSheet(server: server),
            ),
          ),
        ],
      ),
    );
  }

  // ── 2 × 2 Gauge Grid ─────────────────────────────────────────────────────

  Widget _buildGaugeGrid(
    ServerMetrics? m,
    MetricHistory history,
    AlertThresholdProfile thresholds,
    Server server,
  ) {
    final netMax = history.isEmpty
        ? (10 * 1024 * 1024).toDouble()
        : history.netMaxValue;
    final netRxPct = m != null
        ? (m.netRxBytesPerSec / netMax).clamp(0.0, 1.0)
        : 0.0;

    final watchedId = ref.watch(watchedServerIdProvider);
    final isWatching = watchedId == server.id;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: _SectionCard(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
              child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Column(
                children: [
                  MetricGauge(
                    percent: m != null ? m.cpuUsagePercent / 100 : 0,
                    label: 'CPU',
                    valueText: m != null
                        ? '${m.cpuUsagePercent.toStringAsFixed(0)}%'
                        : '—',
                    subText: m != null
                        ? '${m.loadAvg1.toStringAsFixed(2)} avg'
                        : null,
                    color: OrbitalColors.cpu,
                    isAlert: m != null && m.cpuUsagePercent > thresholds.cpu,
                  ),
                  const SizedBox(height: 16),
                  MetricGauge(
                    percent: m != null ? m.diskUsagePercent / 100 : 0,
                    label: 'DISK',
                    valueText: m != null
                        ? '${m.diskUsagePercent.toStringAsFixed(0)}%'
                        : '—',
                    subText: m != null
                        ? ServerMetrics.formatBytes(m.diskUsedBytes)
                        : null,
                    color: OrbitalColors.disk,
                    isAlert: m != null && m.diskUsagePercent > thresholds.disk,
                  ),
                ],
              ),
              Column(
                children: [
                  MetricGauge(
                    percent: m != null ? m.memUsagePercent / 100 : 0,
                    label: 'RAM',
                    valueText: m != null
                        ? '${m.memUsagePercent.toStringAsFixed(0)}%'
                        : '—',
                    subText: m != null
                        ? ServerMetrics.formatKb(m.memUsedKb)
                        : null,
                    color: OrbitalColors.memory,
                    isAlert: m != null && m.memUsagePercent > thresholds.memory,
                  ),
                  const SizedBox(height: 16),
                  MetricGauge(
                    percent: netRxPct,
                    label: 'NET ↓',
                    valueText: m != null
                        ? ServerMetrics.formatBytes(m.netRxBytesPerSec)
                        : '—',
                    subText: m != null
                        ? '↑ ${ServerMetrics.formatBytes(m.netTxBytesPerSec)}'
                        : null,
                    color: OrbitalColors.network,
                  ),
                ],
              ),
            ],
          ),
        ),
            // ── Watch button ────────────────────────────────────────────
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                onTap: () => _toggleWatch(server, m),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    isWatching
                        ? Icons.podcasts_rounded
                        : Icons.podcasts_outlined,
                    key: ValueKey(isWatching),
                    size: 16,
                    color: isWatching
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThresholdsSection(
    Server server,
    AlertThresholdProfile thresholds,
  ) {
    final custom = server.cpuAlertThreshold != null ||
        server.memoryAlertThreshold != null ||
        server.diskAlertThreshold != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: _SectionCard(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.notifications_active_outlined, size: 18),
                  const SizedBox(width: 8),
                  const Text(
                    'Alert Thresholds',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  Text(
                    custom ? 'Custom' : 'App defaults',
                    style: TextStyle(
                      fontSize: 12,
                      color: custom
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).textTheme.bodySmall?.color ?? OrbitalColors.textMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'CPU ${thresholds.cpu.toStringAsFixed(0)}% • RAM ${thresholds.memory.toStringAsFixed(0)}% • Disk ${thresholds.disk.toStringAsFixed(0)}%',
                style: const TextStyle(fontFamily: 'Menlo', fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── History chart + tab selector ──────────────────────────────────────────

  Widget _buildHistorySection(MetricHistory history) {
    const tabs = ['CPU', 'RAM', 'DISK', 'NET'];
    final colors = [
      OrbitalColors.cpu,
      OrbitalColors.memory,
      OrbitalColors.disk,
      OrbitalColors.network,
    ];

    final primary = [
      history.cpuValues,
      history.memoryValues,
      history.diskValues,
      history.netRxValues,
    ];
    final secondary = [null, null, null, history.netTxValues];
    final maxValues = [100.0, 100.0, 100.0, history.netMaxValue];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: _SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 0),
              child: Row(
                children: [
                  const Text(
                    'HISTORY',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: OrbitalColors.textMuted,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${history.length}/$_kMaxSamples samples',
                    style: const TextStyle(
                      fontSize: 11,
                      color: OrbitalColors.textMuted,
                    ),
                  ),
                  const Spacer(),
                  _SegmentedTabs(
                    tabs: tabs,
                    colors: colors,
                    selectedIndex: _chartTab,
                    onTap: (i) => setState(() => _chartTab = i),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
              child: SizedBox(
                height: 120,
                child: MetricHistoryChart(
                  primary: primary[_chartTab],
                  secondary: secondary[_chartTab],
                  primaryColor: colors[_chartTab],
                  secondaryColor: colors[_chartTab].withOpacity(0.45),
                  maxValue: maxValues[_chartTab],
                ),
              ),
            ),
            if (_chartTab == 3)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  children: [
                    _LegendDot(color: OrbitalColors.network, label: 'Download'),
                    const SizedBox(width: 16),
                    _LegendDot(
                      color: OrbitalColors.network.withOpacity(0.45),
                      label: 'Upload',
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── System info tiles ─────────────────────────────────────────────────────

  Widget _buildSystemInfoSection(ServerMetrics? m, Server server) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: _SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader(title: 'SYSTEM'),
            ServerInfoTile(
              showTopDivider: false,
              icon: Icons.computer_rounded,
              label: 'Hostname',
              value: m?.hostname ?? server.host,
              isMonospace: true,
            ),
            ServerInfoTile(
              icon: Icons.memory_rounded,
              label: 'Kernel',
              value: m?.kernelVersion ?? '—',
              isMonospace: true,
            ),
            ServerInfoTile(
              icon: Icons.schedule_rounded,
              label: 'Uptime',
              value: m?.uptimeFormatted ?? '—',
            ),
            ServerInfoTile(
              icon: Icons.apps_rounded,
              label: 'Processes',
              value: m != null ? '${m.processCount}' : '—',
            ),
            ServerInfoTile(
              icon: Icons.show_chart_rounded,
              label: 'Load Average',
              value: m != null
                  ? '${m.loadAvg1.toStringAsFixed(2)}  '
                        '${m.loadAvg5.toStringAsFixed(2)}  '
                        '${m.loadAvg15.toStringAsFixed(2)}'
                  : '—',
              isMonospace: true,
            ),
            if (m?.cpuTempCelsius != null)
              ServerInfoTile(
                icon: Icons.device_thermostat_rounded,
                label: 'CPU Temperature',
                value: '${m!.cpuTempCelsius!.toStringAsFixed(1)} °C',
                valueColor: m.cpuTempCelsius! > 80
                    ? OrbitalColors.danger
                    : m.cpuTempCelsius! > 65
                    ? OrbitalColors.warning
                    : null,
              ),
          ],
        ),
      ),
    );
  }

  // ── Memory breakdown ──────────────────────────────────────────────────────

  Widget _buildMemoryBreakdown(ServerMetrics? m) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: _SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader(title: 'MEMORY'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Column(
                children: [
                  _MemoryBar(metrics: m),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _MemoryLegendItem(
                        color: OrbitalColors.memory,
                        label: 'Used',
                        value: m != null
                            ? ServerMetrics.formatKb(m.memUsedKb)
                            : '—',
                      ),
                      _MemoryLegendItem(
                        color: OrbitalColors.network,
                        label: 'Free',
                        value: m != null
                            ? ServerMetrics.formatKb(m.memAvailableKb)
                            : '—',
                      ),
                      _MemoryLegendItem(
                        color: OrbitalColors.disk,
                        label: 'Swap',
                        value: m != null && m.swapTotalKb > 0
                            ? '${ServerMetrics.formatKb(m.swapUsedKb)} / ${ServerMetrics.formatKb(m.swapTotalKb)}'
                            : 'None',
                      ),
                      _MemoryLegendItem(
                        color: OrbitalColors.textMuted,
                        label: 'Total',
                        value: m != null
                            ? ServerMetrics.formatKb(m.memTotalKb)
                            : '—',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Delete button ─────────────────────────────────────────────────────────

  Widget _buildDeleteButton(Server server) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => context.push(
                '${AppRoutes.servers}/${server.id}/edit',
                extra: server,
              ),
              icon: const Icon(Icons.edit_rounded, size: 18),
              label: const Text('Edit'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                foregroundColor: Theme.of(context).colorScheme.primary,
                side: BorderSide(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.4),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _confirmAndDelete(server),
              icon: const Icon(Icons.delete_rounded, size: 18),
              label: const Text('Delete'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                foregroundColor: OrbitalColors.danger,
                side: BorderSide(color: OrbitalColors.danger.withOpacity(0.4)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Delete confirmation ───────────────────────────────────────────────────

  Future<void> _confirmAndDelete(Server server) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: Theme.of(context).dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: OrbitalColors.danger.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.delete_rounded,
                color: OrbitalColors.danger,
                size: 26,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Delete "${server.displayName}"?',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'The server and its stored credentials will be\npermanently removed. This cannot be undone.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color:
                    Theme.of(context).textTheme.bodySmall?.color ??
                    OrbitalColors.textMuted,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      foregroundColor: Theme.of(
                        context,
                      ).colorScheme.onSurfaceVariant,
                      side: BorderSide(color: Theme.of(context).dividerColor),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: OrbitalColors.danger,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Delete',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && mounted) {
      await ref.read(sshManagerProvider).disconnect(server.id);
      await ref.read(serverRepositoryProvider).deleteServer(server.id);
      if (mounted) context.pop();
    }
  }
}

// ── _kMaxSamples alias (for the history header sample-count label) ────────────

const _kMaxSamples = kMetricHistoryMaxSamples;

// ═════════════════════════════════════════════════════════════════════════════
// Supporting widgets (file-private)
// ═════════════════════════════════════════════════════════════════════════════

// ── _StatusChip ───────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  final ServerConnectionState? state;

  const _StatusChip({required this.state});

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;
    final bool spinning;

    switch (state?.status) {
      case ConnectionStatus.connected:
        color = OrbitalColors.online;
        label = 'Online';
        spinning = false;
      case ConnectionStatus.unsupportedPlatform:
        color = OrbitalColors.warning;
        label = 'Connected';
        spinning = false;
      case ConnectionStatus.connecting:
        color = OrbitalColors.warning;
        label = 'Connecting';
        spinning = true;
      case ConnectionStatus.error:
        color = OrbitalColors.danger;
        label = 'Error';
        spinning = false;
      default:
        color = OrbitalColors.offline;
        label = 'Offline';
        spinning = false;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (spinning)
            SizedBox(
              width: 7,
              height: 7,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: color),
            )
          else
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ── _ActionButton ─────────────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white.withOpacity(0.08)
                  : Colors.black.withOpacity(0.08),
            ),
            boxShadow: Theme.of(context).brightness == Brightness.dark
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── _SectionCard ──────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final Widget child;

  const _SectionCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white.withOpacity(0.08)
              : Colors.black.withOpacity(0.08),
        ),
        boxShadow: Theme.of(context).brightness == Brightness.dark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
      ),
      child: child,
    );
  }
}

// ── _SectionHeader ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color:
              Theme.of(context).textTheme.bodySmall?.color ??
              OrbitalColors.textMuted,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

// ── _SegmentedTabs ────────────────────────────────────────────────────────────

class _SegmentedTabs extends StatelessWidget {
  final List<String> tabs;
  final List<Color> colors;
  final int selectedIndex;
  final ValueChanged<int> onTap;

  const _SegmentedTabs({
    required this.tabs,
    required this.colors,
    required this.selectedIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Theme.of(context).inputDecorationTheme.fillColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(tabs.length, (i) {
          final selected = i == selectedIndex;
          return GestureDetector(
            onTap: () => onTap(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeInOut,
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: selected
                    ? colors[i].withOpacity(0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(
                tabs[i],
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? colors[i]
                      : Theme.of(context).textTheme.bodySmall?.color ??
                            OrbitalColors.textMuted,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ── _LegendDot ────────────────────────────────────────────────────────────────

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color:
                Theme.of(context).textTheme.bodySmall?.color ??
                OrbitalColors.textMuted,
          ),
        ),
      ],
    );
  }
}

// ── _MemoryBar ────────────────────────────────────────────────────────────────

class _MemoryBar extends StatelessWidget {
  final ServerMetrics? metrics;

  const _MemoryBar({required this.metrics});

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    if (m == null || m.memTotalKb == 0) {
      return Container(
        height: 10,
        decoration: BoxDecoration(
          color: Theme.of(context).inputDecorationTheme.fillColor,
          borderRadius: BorderRadius.circular(5),
        ),
      );
    }

    final total = m.memTotalKb.toDouble();
    final usedFrac = (m.memUsedKb / total).clamp(0.0, 1.0);
    final freeFrac = (m.memAvailableKb / total).clamp(0.0, 1.0 - usedFrac);

    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: SizedBox(
        height: 10,
        child: Row(
          children: [
            Flexible(
              flex: (usedFrac * 1000).round(),
              child: Container(color: OrbitalColors.memory),
            ),
            Flexible(
              flex: (freeFrac * 1000).round(),
              child: Container(color: OrbitalColors.network.withOpacity(0.7)),
            ),
            Flexible(
              flex: ((1.0 - usedFrac - freeFrac).clamp(0.0, 1.0) * 1000)
                  .round()
                  .clamp(1, 1000),
              child: Container(
                color: Theme.of(context).inputDecorationTheme.fillColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── _MemoryLegendItem ─────────────────────────────────────────────────────────

class _MemoryLegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final String value;

  const _MemoryLegendItem({
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color:
                    Theme.of(context).textTheme.bodySmall?.color ??
                    OrbitalColors.textMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface,
            fontFamily: 'Menlo',
          ),
        ),
      ],
    );
  }
}

// ── _ErrorBanner ──────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: OrbitalColors.danger.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: OrbitalColors.danger.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 16,
            color: OrbitalColors.danger,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12, color: OrbitalColors.danger),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ── _LoadingScaffold ──────────────────────────────────────────────────────────

class _LoadingScaffold extends StatelessWidget {
  const _LoadingScaffold();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 20,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          onPressed: () => context.pop(),
        ),
      ),
      body: Center(
        child: CircularProgressIndicator(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

// ── _ErrorScaffold ────────────────────────────────────────────────────────────

class _ErrorScaffold extends StatelessWidget {
  final String message;

  const _ErrorScaffold({required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 20,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          onPressed: () => context.pop(),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: OrbitalColors.danger,
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── _ConnectingState ──────────────────────────────────────────────────────────

class _ConnectingState extends StatelessWidget {
  const _ConnectingState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            color: Theme.of(context).colorScheme.primary,
            strokeWidth: 2,
          ),
          const SizedBox(height: 20),
          Text(
            'Establishing SSH connection…',
            style: TextStyle(
              fontSize: 14,
              color:
                  Theme.of(context).textTheme.bodySmall?.color ??
                  OrbitalColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

// ── _UnsupportedPlatformBanner ────────────────────────────────────────────────

class _UnsupportedPlatformBanner extends StatelessWidget {
  final String osName;

  const _UnsupportedPlatformBanner({required this.osName});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: OrbitalColors.warning.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: OrbitalColors.warning.withOpacity(0.25)),
        ),
        child: Column(
          children: [
            const Icon(
              Icons.info_outline_rounded,
              size: 40,
              color: OrbitalColors.warning,
            ),
            const SizedBox(height: 16),
            Text(
              'Metrics Not Supported',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$osName does not support the Linux /proc metrics.\n'
              'Terminal and Docker still work normally.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color:
                    Theme.of(context).textTheme.bodySmall?.color ??
                    OrbitalColors.textMuted,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── _ConnectionErrorState ─────────────────────────────────────────────────────

class _ConnectionErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ConnectionErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: OrbitalColors.danger.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.wifi_off_rounded,
                size: 30,
                color: OrbitalColors.danger,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Connection Failed',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color:
                    Theme.of(context).textTheme.bodySmall?.color ??
                    OrbitalColors.textMuted,
              ),
            ),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: onRetry,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.35),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.refresh_rounded,
                      size: 16,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Retry Connection',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
