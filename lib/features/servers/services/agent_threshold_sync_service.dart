import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/alert_thresholds.dart';
import '../../../data/database/app_database.dart';
import '../../../data/models/server_model.dart';
import '../../../data/repositories/server_repository.dart';
import '../../../data/settings/settings_repository.dart';
import '../../../ssh/ssh_key_service.dart';

const _kContainerImage = 'ghcr.io/jonathanintheclouds/orbital-agent:latest';
const _kContainerName = 'orbital-agent';
const _kAgentConfigDir = '/etc/orbital-agent';
const _kAgentConfigPath = '/etc/orbital-agent/config.json';

class AgentThresholdSyncService {
  AgentThresholdSyncService(this._ref);

  final Ref _ref;

  Future<int> syncServersUsingDefaults(
    AlertThresholdProfile appDefaults,
  ) async {
    final repo = _ref.read(serverRepositoryProvider);
    final servers = await repo.getAllServers();
    var updated = 0;
    for (final server in servers) {
      final usesDefaults =
          server.cpuAlertThreshold == null &&
          server.memoryAlertThreshold == null &&
          server.diskAlertThreshold == null;
      if (!usesDefaults) continue;
      final ok = await syncServer(server, appDefaults);
      if (ok) updated++;
    }
    return updated;
  }

  Future<bool> syncServer(
    Server server,
    AlertThresholdProfile appDefaults,
  ) async {
    final repo = _ref.read(serverRepositoryProvider);
    final settings = _ref.read(settingsProvider);
    final credential = await repo.getCredentialForServer(server);
    if (credential == null) return false;
    final keyService = _ref.read(sshKeyServiceProvider);

    final thresholds = AlertThresholdProfile.effectiveForServer(
      server,
      appDefaults,
    );

    SSHClient? client;
    try {
      final socket = await SSHSocket.connect(
        server.host,
        server.port,
        timeout: const Duration(seconds: 10),
      );
      client = keyService.createClient(
        socket: socket,
        username: server.username,
        credential: credential,
      );
      await client.authenticated;

      final runtime = await _findContainerRuntime(client);
      if (runtime != null) {
        final serverId = server.relayServerId;
        final serverName = server.displayName;
        final relayUrl = '${settings.relayUrl}/alert';
        final authToken = settings.relayAuthToken;
        final cpu = thresholds.cpu.toStringAsFixed(0);
        final ram = thresholds.memory.toStringAsFixed(0);
        final disk = thresholds.disk.toStringAsFixed(0);

        await _ssh(
          client,
          'sudo $runtime rm -f $_kContainerName 2>/dev/null || true',
        );
        await _ssh(
          client,
          'sudo $runtime run -d '
          '--pid=host '
          '--restart=always '
          '--name $_kContainerName '
          '-e SERVER_ID="$serverId" '
          '-e SERVER_NAME="$serverName" '
          '-e RELAY_URL="$relayUrl" '
          '-e AUTH_TOKEN="$authToken" '
          '-e CPU_THRESHOLD="$cpu" '
          '-e RAM_THRESHOLD="$ram" '
          '-e DISK_THRESHOLD="$disk" '
          '$_kContainerImage',
        );
        return true;
      }

      final hasService =
          await _sshExitCode(
            client,
            'sudo systemctl cat orbital-agent > /dev/null 2>&1',
          ) ==
          0;
      if (!hasService) return false;

      final config = jsonEncode({
        'server_id': server.relayServerId,
        'server_name': server.displayName,
        'relay_url': '${settings.relayUrl}/alert',
        'auth_token': settings.relayAuthToken,
        'poll_interval_seconds': 30,
        'cooldown_minutes': 5,
        'thresholds': {
          'cpu_percent': thresholds.cpu.round(),
          'ram_percent': thresholds.memory.round(),
          'disk_percent': thresholds.disk.round(),
        },
      });

      await _ssh(client, 'sudo mkdir -p $_kAgentConfigDir');
      await _ssh(
        client,
        "printf '%s' '${config.replaceAll("'", "'\\''")}' | sudo tee $_kAgentConfigPath > /dev/null",
      );
      await _ssh(client, 'sudo systemctl restart orbital-agent');
      return true;
    } catch (_) {
      return false;
    } finally {
      client?.close();
    }
  }

  Future<String?> _findContainerRuntime(SSHClient client) async {
    for (final runtime in ['docker', 'podman']) {
      final hasRuntime =
          await _sshExitCode(client, '$runtime info > /dev/null 2>&1') == 0;
      if (!hasRuntime) continue;
      final hasContainer =
          await _sshExitCode(
            client,
            'sudo $runtime inspect $_kContainerName > /dev/null 2>&1',
          ) ==
          0;
      if (hasContainer) return runtime;
    }
    return null;
  }

  Future<String> _ssh(SSHClient client, String command) async {
    final session = await client.execute(command);
    final out = StringBuffer();
    await for (final chunk in session.stdout) {
      out.write(utf8.decode(chunk, allowMalformed: true));
    }
    await session.done;
    return out.toString();
  }

  Future<int> _sshExitCode(SSHClient client, String command) async {
    final session = await client.execute(command);
    await session.done;
    return session.exitCode ?? 1;
  }
}

final agentThresholdSyncServiceProvider = Provider<AgentThresholdSyncService>(
  (ref) => AgentThresholdSyncService(ref),
);
