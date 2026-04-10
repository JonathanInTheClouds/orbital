import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/orbital_logger.dart';
import '../../../ssh/ssh_connection_manager.dart';
import 'docker_models.dart';

// ── DockerCommandRunner ───────────────────────────────────────────────────────

class DockerCommandRunner {
  final int serverId;
  final SshConnectionManager _manager;

  static const _tag = 'Docker';

  DockerCommandRunner({
    required this.serverId,
    required SshConnectionManager manager,
  }) : _manager = manager;

  Future<String> _run(String command) async {
    final conn = _manager.getConnection(serverId);
    if (conn == null || !conn.currentState.isConnected) {
      throw StateError('No active SSH connection for server $serverId');
    }
    return conn.execute(command);
  }

  Future<List<DockerContainer>> listContainers() async {
    OrbitalLogger.instance.debug(
      _tag,
      'Listing containers for server $serverId',
    );
    try {
      final raw = await _run("docker ps -a --format '{{json .}}'");
      final containers = _parseJsonLines(
        raw,
      ).map((j) => DockerContainer.fromDockerJson(j)).toList();

      final running = containers.where((c) => c.state.isRunning).toList();
      if (running.isNotEmpty) {
        final statsMap = await _fetchStats();
        return containers.map((c) {
          final stats = statsMap[c.shortId] ?? statsMap[c.id];
          return stats != null ? c.withStats(stats) : c;
        }).toList();
      }
      return containers;
    } catch (e) {
      OrbitalLogger.instance.error(_tag, 'listContainers failed: $e');
      rethrow;
    }
  }

  Future<Map<String, DockerStats>> _fetchStats() async {
    try {
      final raw = await _run("docker stats --no-stream --format '{{json .}}'");
      final map = <String, DockerStats>{};
      for (final j in _parseJsonLines(raw)) {
        final s = DockerStats.fromDockerJson(j);
        map[s.containerId] = s;
        if (s.containerId.length >= 12) {
          map[s.containerId.substring(0, 12)] = s;
        }
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  Future<List<DockerImage>> listImages() async {
    OrbitalLogger.instance.debug(_tag, 'Listing images for server $serverId');
    try {
      final raw = await _run("docker images --format '{{json .}}'");
      return _parseJsonLines(
        raw,
      ).map((j) => DockerImage.fromDockerJson(j)).toList();
    } catch (e) {
      OrbitalLogger.instance.error(_tag, 'listImages failed: $e');
      rethrow;
    }
  }

  Future<String> fetchLogs(String containerId, {int tail = 200}) async {
    OrbitalLogger.instance.debug(_tag, 'Fetching logs for $containerId');
    try {
      return await _run('docker logs --tail $tail $containerId 2>&1');
    } catch (e) {
      OrbitalLogger.instance.error(_tag, 'fetchLogs failed: $e');
      rethrow;
    }
  }

  Future<void> startContainer(String id) async {
    OrbitalLogger.instance.info(_tag, 'Starting container $id');
    await _run('docker start $id');
  }

  Future<void> stopContainer(String id) async {
    OrbitalLogger.instance.info(_tag, 'Stopping container $id');
    await _run('docker stop $id');
  }

  Future<void> restartContainer(String id) async {
    OrbitalLogger.instance.info(_tag, 'Restarting container $id');
    await _run('docker restart $id');
  }

  Future<void> removeContainer(String id, {bool force = false}) async {
    OrbitalLogger.instance.info(_tag, 'Removing container $id (force: $force)');
    await _run('docker rm${force ? ' -f' : ''} $id');
  }

  Future<void> removeImage(String id, {bool force = false}) async {
    OrbitalLogger.instance.info(_tag, 'Removing image $id (force: $force)');
    await _run('docker rmi${force ? ' -f' : ''} $id');
  }

  List<Map<String, dynamic>> _parseJsonLines(String raw) {
    final results = <Map<String, dynamic>>[];
    for (final line in raw.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map<String, dynamic>) results.add(decoded);
      } catch (_) {}
    }
    return results;
  }
}

// ── DockerState ───────────────────────────────────────────────────────────────

class DockerState {
  final List<DockerContainer> containers;
  final List<DockerImage> images;
  final bool isLoading;
  final String? errorMessage;
  final DateTime? lastUpdated;

  const DockerState({
    this.containers = const [],
    this.images = const [],
    this.isLoading = false,
    this.errorMessage,
    this.lastUpdated,
  });

  DockerState copyWith({
    List<DockerContainer>? containers,
    List<DockerImage>? images,
    bool? isLoading,
    String? errorMessage,
    DateTime? lastUpdated,
  }) => DockerState(
    containers: containers ?? this.containers,
    images: images ?? this.images,
    isLoading: isLoading ?? this.isLoading,
    errorMessage: errorMessage,
    lastUpdated: lastUpdated ?? this.lastUpdated,
  );
}

// ── DockerManagerNotifier ─────────────────────────────────────────────────────
// Holds DockerState for ALL servers in a single Map, same pattern as
// MetricHistoryNotifier — avoids FamilyNotifier which doesn't exist in
// Riverpod 3.x.

class DockerManagerNotifier extends Notifier<Map<int, DockerState>> {
  final Map<int, Timer> _timers = {};

  @override
  Map<int, DockerState> build() {
    ref.onDispose(() {
      for (final t in _timers.values) {
        t.cancel();
      }
    });
    return const {};
  }

  // ── Internal state helpers ────────────────────────────────────────────────

  DockerState _stateFor(int serverId) => state[serverId] ?? const DockerState();

  void _setState(int serverId, DockerState s) {
    state = {...state, serverId: s};
  }

  DockerCommandRunner _runner(int serverId) => DockerCommandRunner(
    serverId: serverId,
    manager: ref.read(sshManagerProvider),
  );

  // ── Polling lifecycle ─────────────────────────────────────────────────────

  /// Call this when the Docker screen opens for a server.
  void startPolling(int serverId) {
    if (_timers.containsKey(serverId)) return;
    _setState(serverId, const DockerState(isLoading: true));
    refreshContainers(serverId);
    _timers[serverId] = Timer.periodic(
      const Duration(seconds: 10),
      (_) => refreshContainers(serverId),
    );
  }

  void stopPolling(int serverId) {
    _timers[serverId]?.cancel();
    _timers.remove(serverId);
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> refreshContainers(int serverId) async {
    _setState(
      serverId,
      _stateFor(serverId).copyWith(isLoading: true, errorMessage: null),
    );
    try {
      final containers = await _runner(serverId).listContainers();
      _setState(
        serverId,
        _stateFor(serverId).copyWith(
          containers: containers,
          isLoading: false,
          lastUpdated: DateTime.now(),
        ),
      );
    } catch (e) {
      _setState(
        serverId,
        _stateFor(
          serverId,
        ).copyWith(isLoading: false, errorMessage: e.toString()),
      );
    }
  }

  Future<void> refreshImages(int serverId) async {
    try {
      final images = await _runner(serverId).listImages();
      _setState(serverId, _stateFor(serverId).copyWith(images: images));
    } catch (e) {
      _setState(
        serverId,
        _stateFor(serverId).copyWith(errorMessage: e.toString()),
      );
    }
  }

  Future<String> fetchLogs(int serverId, String containerId) =>
      _runner(serverId).fetchLogs(containerId);

  Future<void> startContainer(int serverId, String id) async {
    await _runner(serverId).startContainer(id);
    await refreshContainers(serverId);
  }

  Future<void> stopContainer(int serverId, String id) async {
    await _runner(serverId).stopContainer(id);
    await refreshContainers(serverId);
  }

  Future<void> restartContainer(int serverId, String id) async {
    await _runner(serverId).restartContainer(id);
    await refreshContainers(serverId);
  }

  Future<void> removeContainer(
    int serverId,
    String id, {
    bool force = false,
  }) async {
    await _runner(serverId).removeContainer(id, force: force);
    await refreshContainers(serverId);
  }

  Future<void> removeImage(
    int serverId,
    String id, {
    bool force = false,
  }) async {
    await _runner(serverId).removeImage(id, force: force);
    await refreshImages(serverId);
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

final dockerManagerProvider =
    NotifierProvider<DockerManagerNotifier, Map<int, DockerState>>(
      DockerManagerNotifier.new,
    );

/// Per-server selector — same pattern as metricHistoryProvider.
final dockerProvider = Provider.family<DockerState, int>((ref, serverId) {
  return ref.watch(
    dockerManagerProvider.select((map) => map[serverId] ?? const DockerState()),
  );
});
