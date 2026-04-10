import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/alert_thresholds.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/database/app_database.dart';
import '../../../data/models/server_model.dart';
import '../../../data/settings/settings_repository.dart';
import '../../../ssh/ssh_connection_manager.dart';
import '../../../ssh/ssh_models.dart';

class ServerCard extends ConsumerWidget {
  final Server server;
  final VoidCallback onTap;

  const ServerCard({super.key, required this.server, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionAsync = ref.watch(serverConnectionProvider(server));
    final settings = ref.watch(settingsProvider);
    final thresholds = AlertThresholdProfile.effectiveForServer(
      server,
      AlertThresholdProfile(
        cpu: settings.cpuAlertThreshold,
        memory: settings.memoryAlertThreshold,
        disk: settings.diskAlertThreshold,
      ),
    );
    final hasCustomThresholds = server.cpuAlertThreshold != null ||
        server.memoryAlertThreshold != null ||
        server.diskAlertThreshold != null;
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
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
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ],
        ),
        child: Column(
          children: [
            _buildHeader(context, connectionAsync, hasCustomThresholds),
            Divider(
            height: 1,
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white.withOpacity(0.08)
                : Colors.black.withOpacity(0.08),
          ),
            _buildMetrics(context, connectionAsync, thresholds),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    AsyncValue<ServerConnectionState> connectionAsync,
    bool hasCustomThresholds,
  ) {
    final state = connectionAsync.asData?.value;
    final textMuted =
        Theme.of(context).textTheme.bodySmall?.color ?? OrbitalColors.textMuted;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          _buildServerIcon(context),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  server.displayName,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  state?.metrics?.hostname ?? server.connectionString,
                  style: TextStyle(
                    fontSize: 13,
                    color: textMuted,
                    fontFamily: 'Menlo',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (hasCustomThresholds)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Custom thresholds',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _buildStatusBadge(state),
        ],
      ),
    );
  }

  Widget _buildServerIcon(BuildContext context) {
    final color = server.displayColor ?? Theme.of(context).colorScheme.primary;
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Icon(server.displayIcon, color: color, size: 22),
    );
  }

  Widget _buildStatusBadge(ServerConnectionState? state) {
    final Color color;
    final String label;

    switch (state?.status) {
      case ConnectionStatus.connected:
        color = OrbitalColors.online;
        label = 'Online';
      case ConnectionStatus.unsupportedPlatform:
        color = OrbitalColors.warning;
        label = 'Connected';
      case ConnectionStatus.connecting:
        color = OrbitalColors.warning;
        label = 'Connecting';
      case ConnectionStatus.error:
        color = OrbitalColors.danger;
        label = 'Error';
      default:
        color = OrbitalColors.offline;
        label = 'Offline';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (state?.status == ConnectionStatus.connecting)
            SizedBox(
              width: 6,
              height: 6,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: color),
            )
          else
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetrics(
    BuildContext context,
    AsyncValue<ServerConnectionState> connectionAsync,
    AlertThresholdProfile thresholds,
  ) {
    final state = connectionAsync.asData?.value;
    final metrics = state?.metrics;
    final textMuted =
        Theme.of(context).textTheme.bodySmall?.color ?? OrbitalColors.textMuted;

    // For unsupported platforms show a subtle indicator instead of blank dashes
    if (state?.isUnsupportedPlatform == true) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.info_outline_rounded,
              size: 14,
              color: textMuted,
            ),
            const SizedBox(width: 6),
            Text(
              'Metrics unavailable — ${state!.osName ?? 'unsupported OS'}',
              style: TextStyle(
                fontSize: 12,
                color: textMuted,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          _buildMetricItem(
            context: context,
            label: 'CPU',
            value: metrics != null
                ? '${metrics.cpuUsagePercent.toStringAsFixed(0)}%'
                : '—',
            color: OrbitalColors.cpu,
            icon: Icons.memory_rounded,
            alert: metrics != null && metrics.cpuUsagePercent > thresholds.cpu,
          ),
          _buildDivider(context),
          _buildMetricItem(
            context: context,
            label: 'RAM',
            value: metrics != null
                ? '${metrics.memUsagePercent.toStringAsFixed(0)}%'
                : '—',
            color: OrbitalColors.memory,
            icon: Icons.storage_rounded,
            alert: metrics != null && metrics.memUsagePercent > thresholds.memory,
          ),
          _buildDivider(context),
          _buildMetricItem(
            context: context,
            label: 'DISK',
            value: metrics != null
                ? '${metrics.diskUsagePercent.toStringAsFixed(0)}%'
                : '—',
            color: OrbitalColors.disk,
            icon: Icons.disc_full_rounded,
            alert: metrics != null && metrics.diskUsagePercent > thresholds.disk,
          ),
          _buildDivider(context),
          _buildMetricItem(
            context: context,
            label: 'NET↑',
            value: metrics != null
                ? ServerMetrics.formatBytes(metrics.netTxBytesPerSec) + '/s'
                : '—',
            color: OrbitalColors.network,
            icon: Icons.swap_vert_rounded,
          ),
        ],
      ),
    );
  }

  Widget _buildMetricItem({
    required BuildContext context,
    required String label,
    required String value,
    required Color color,
    required IconData icon,
    bool alert = false,
  }) {
    final displayColor = alert ? OrbitalColors.danger : color;
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 16, color: displayColor.withOpacity(0.7)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: value == '—'
                  ? Theme.of(context).textTheme.bodySmall?.color ??
                        OrbitalColors.textMuted
                  : displayColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color:
                  Theme.of(context).textTheme.bodySmall?.color ??
                  OrbitalColors.textMuted,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider(BuildContext context) {
    final color = Theme.of(context).brightness == Brightness.dark
        ? Colors.white.withOpacity(0.08)
        : Colors.black.withOpacity(0.08);
    return Container(width: 1, height: 36, color: color);
  }
}
