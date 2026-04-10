import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/server_model.dart';
import '../../../data/repositories/server_repository.dart';
import '../../../services/dynamic_island_service.dart';
import '../../../ssh/ssh_connection_manager.dart';

// ── Watched server ID ─────────────────────────────────────────────────────────

class WatchedServerIdNotifier extends Notifier<int?> {
  @override
  int? build() => null;

  void setWatchedId(int? id) => state = id;
}

/// The ID of the server currently pinned to the Dynamic Island.
/// null → nothing is being watched.
final watchedServerIdProvider =
    NotifierProvider<WatchedServerIdNotifier, int?>(
  WatchedServerIdNotifier.new,
);

// ── Background updater ────────────────────────────────────────────────────────

/// A reactive provider that keeps the Dynamic Island in sync with live metrics.
/// Watch this from a long-lived widget (ShellScreen) so it stays alive even
/// when the user navigates away from the server detail screen.
final dynamicIslandUpdaterProvider = Provider<void>((ref) {
  final watchedId = ref.watch(watchedServerIdProvider);
  if (watchedId == null) return;

  final serverAsync = ref.watch(serverByIdProvider(watchedId));
  final server = serverAsync.asData?.value;
  if (server == null) return;

  final connectionAsync = ref.watch(serverConnectionProvider(server));
  final state = connectionAsync.asData?.value;

  // Push the update after the current build frame to avoid calling a platform
  // channel during a widget rebuild.
  Future.microtask(() {
    final metrics = state?.metrics;
    if (metrics != null) {
      DynamicIslandService.updateMetrics(
        serverName: server.displayName,
        cpu: metrics.cpuUsagePercent,
        ram: metrics.memUsagePercent,
        disk: metrics.diskUsagePercent,
        isConnected: state?.isConnected ?? false,
      );
    }
  });
});
