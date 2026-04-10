import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/database/app_database.dart';
import '../../../data/repositories/server_repository.dart';
import '../../../ssh/ssh_connection_manager.dart';
import '../../../ssh/ssh_models.dart';
import '../mock/mock_metric_generator.dart';
import 'server_detail_screen.dart';

// ── Mock server definition ────────────────────────────────────────────────────

/// Sentinel ID used for the mock server. Must not collide with real DB IDs
/// (which start at 1), so we use a large negative value.
const _kMockServerId = -1;

/// A fake [Server] instance that matches the Drift-generated data class.
/// All fields must be provided because Drift generates non-nullable constructors.
final _mockServer = Server(
  id: _kMockServerId,
  name: 'prod-web-01',
  host: '192.168.1.100',
  port: 22,
  username: 'ubuntu',
  authType: 0, // AuthType.password
  credentialStorageKey: 'mock_key',
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
);

// ── ServerDetailPreview ───────────────────────────────────────────────────────

/// Wraps [ServerDetailScreen] inside a [ProviderScope] that overrides:
///   - [serverByIdProvider] → returns [_mockServer] immediately
///   - [serverConnectionProvider] → returns [MockMetricGenerator.stream()]
///
/// The real [ServerDetailScreen] code is completely unchanged; it simply
/// receives mock data through the same provider contracts it already uses.
class ServerDetailPreview extends StatelessWidget {
  const ServerDetailPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        // Override the server lookup so serverByIdProvider(_kMockServerId)
        // resolves without touching the database.
        serverByIdProvider(_kMockServerId).overrideWith(
          (ref) async => _mockServer,
        ),

        // Override the SSH stream so the detail screen gets live mock data.
        serverConnectionProvider(_mockServer).overrideWith(
          (ref) => MockMetricGenerator.stream(),
        ),
      ],
      child: const ServerDetailScreen(
        serverId: '$_kMockServerId',
      ),
    );
  }
}
