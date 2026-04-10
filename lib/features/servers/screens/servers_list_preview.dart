import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/database/app_database.dart';
import '../../../ssh/ssh_connection_manager.dart';
import '../mock/mock_metric_generator.dart';
import '../widgets/server_card.dart';
import '../widgets/servers_empty_state.dart';

// ── Mock servers ──────────────────────────────────────────────────────────────

final _mockServers = [
  Server(
    id: -1,
    name: 'prod-web-01',
    host: '192.168.1.100',
    port: 22,
    username: 'ubuntu',
    authType: 0,
    credentialStorageKey: 'mock_key_1',
    label: null,
    notes: null,
    tags: null,
    color: OrbitalColors.accent.value,
    createdAt: DateTime(2025, 1, 15),
    lastConnectedAt: null,
    cpuAlertThreshold: null,
    memoryAlertThreshold: null,
    diskAlertThreshold: null,
    alertsEnabled: true,
  ),
  Server(
    id: -2,
    name: 'prod-db-01',
    host: '192.168.1.101',
    port: 22,
    username: 'postgres',
    authType: 0,
    credentialStorageKey: 'mock_key_2',
    label: null,
    notes: null,
    tags: null,
    color: OrbitalColors.memory.value,
    createdAt: DateTime(2025, 2, 3),
    lastConnectedAt: null,
    cpuAlertThreshold: null,
    memoryAlertThreshold: null,
    diskAlertThreshold: null,
    alertsEnabled: true,
  ),
  Server(
    id: -3,
    name: 'staging-api',
    host: '10.0.0.55',
    port: 2222,
    username: 'deploy',
    authType: 1,
    credentialStorageKey: 'mock_key_3',
    label: null,
    notes: null,
    tags: null,
    color: OrbitalColors.network.value,
    createdAt: DateTime(2025, 3, 10),
    lastConnectedAt: null,
    cpuAlertThreshold: null,
    memoryAlertThreshold: null,
    diskAlertThreshold: null,
    alertsEnabled: true,
  ),
];

// ── ServersListPreview ────────────────────────────────────────────────────────

/// Renders the real [ServersScreen] UI (AppBar + ServerCards) populated with
/// mock servers. Each card shows live oscillating metrics from
/// [MockMetricGenerator]. Tapping any card navigates to [ServerDetailPreview]
/// via the existing `/servers/preview` route.
class ServersListPreview extends StatelessWidget {
  const ServersListPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        // Give each mock server its own independent metric stream so the
        // cards all animate with slightly different values.
        for (final server in _mockServers)
          serverConnectionProvider(server).overrideWith(
            (ref) => MockMetricGenerator.stream(),
          ),
      ],
      child: const _ServersListPreviewBody(),
    );
  }
}

class _ServersListPreviewBody extends StatelessWidget {
  const _ServersListPreviewBody();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OrbitalColors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          _buildAppBar(context),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ServerCard(
                    server: _mockServers[index],
                    // All cards drop into the same detail preview.
                    onTap: () => context.push('/servers/preview'),
                  ),
                ),
                childCount: _mockServers.length,
              ),
            ),
          ),
        ],
      ),
    );
  }

  SliverAppBar _buildAppBar(BuildContext context) {
    return SliverAppBar(
      floating: true,
      pinned: false,
      snap: true,
      centerTitle: true,
      backgroundColor: OrbitalColors.background,
      surfaceTintColor: Colors.transparent,
      expandedHeight: 100,
      leading: IconButton(
        icon: const Icon(
          Icons.arrow_back_ios_new_rounded,
          size: 20,
          color: OrbitalColors.textSecondary,
        ),
        onPressed: () => context.pop(),
      ),
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.only(bottom: 16),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Orbital',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: OrbitalColors.textPrimary,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: OrbitalColors.accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: OrbitalColors.accent.withOpacity(0.25),
                ),
              ),
              child: const Text(
                'Preview',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: OrbitalColors.accent,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ],
        ),
        background: Container(color: OrbitalColors.background),
      ),
      actions: [
        IconButton(
          icon: const Icon(
            Icons.search_rounded,
            color: OrbitalColors.textSecondary,
          ),
          onPressed: () {},
        ),
        IconButton(
          icon: const Icon(
            Icons.tune_rounded,
            color: OrbitalColors.textSecondary,
          ),
          onPressed: () {},
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}
