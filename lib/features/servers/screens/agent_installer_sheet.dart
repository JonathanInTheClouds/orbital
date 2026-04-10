import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/models/alert_thresholds.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/database/app_database.dart';
import '../../../data/database/tables.dart';
import '../../../data/models/server_model.dart';
import '../../../data/repositories/server_repository.dart';
import '../../../data/settings/settings_repository.dart';

// ── Constants ─────────────────────────────────────────────────────────────────

const _kGithubOwner = 'JonathanInTheClouds';
const _kGithubRepo = 'orbital';
const _kAgentSourceRef = 'main';
const _kPreferSourceBuild = true;
const _kContainerImage = 'ghcr.io/jonathanintheclouds/orbital-agent:latest';
const _kContainerName = 'orbital-agent';
const _kAgentInstallPath = '/usr/local/bin/orbital-agent';
const _kAgentConfigDir = '/etc/orbital-agent';
const _kAgentConfigPath = '/etc/orbital-agent/config.json';
const _kServicePath = '/etc/systemd/system/orbital-agent.service';

// ── Models ────────────────────────────────────────────────────────────────────

enum _StepStatus { pending, running, done, failed, skipped }

class _Step {
  final String label;
  _StepStatus status;
  String? detail;
  _Step(this.label) : status = _StepStatus.pending;
}

enum _InstallMethod { unknown, container, binary }

enum _AgentState {
  checking,
  notInstalled,
  running,
  stopped,
  installing,
  uninstalling,
}

// ── AgentInstallerSheet ───────────────────────────────────────────────────────

class AgentInstallerSheet extends ConsumerStatefulWidget {
  final Server server;
  const AgentInstallerSheet({super.key, required this.server});

  @override
  ConsumerState<AgentInstallerSheet> createState() =>
      _AgentInstallerSheetState();
}

class _AgentInstallerSheetState extends ConsumerState<AgentInstallerSheet> {
  late List<_Step> _steps;
  _AgentState _agentState = _AgentState.checking;
  _InstallMethod _method = _InstallMethod.unknown;
  String? _runtime;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _resetSteps();
    WidgetsBinding.instance.addPostFrameCallback((_) => _detectAgent());
  }

  void _resetSteps() {
    _steps = [
      _Step('Connect to server'),
      _Step('Detect architecture'),
      _Step('Detect container runtime'),
      _Step('Pull / download agent'),
      _Step('Write configuration'),
      _Step('Start agent'),
      _Step('Verify agent is running'),
    ];
  }

  // ── Detect ────────────────────────────────────────────────────────────────

  Future<void> _detectAgent() async {
    setState(() => _agentState = _AgentState.checking);
    SSHClient? client;
    try {
      client = await _connect();

      // Check container first
      final dockerRunning = await _sshExitCode(
        client,
        'docker inspect -f "{{.State.Status}}" $_kContainerName 2>/dev/null | grep -q running',
      );
      if (dockerRunning == 0) {
        _runtime = 'docker';
        _method = _InstallMethod.container;
        setState(() => _agentState = _AgentState.running);
        return;
      }

      final podmanRunning = await _sshExitCode(
        client,
        'podman inspect -f "{{.State.Status}}" $_kContainerName 2>/dev/null | grep -q running',
      );
      if (podmanRunning == 0) {
        _runtime = 'podman';
        _method = _InstallMethod.container;
        setState(() => _agentState = _AgentState.running);
        return;
      }

      // Check if container exists but stopped
      final dockerExists = await _sshExitCode(
        client,
        'docker inspect $_kContainerName > /dev/null 2>&1',
      );
      if (dockerExists == 0) {
        _runtime = 'docker';
        _method = _InstallMethod.container;
        setState(() => _agentState = _AgentState.stopped);
        return;
      }

      final podmanExists = await _sshExitCode(
        client,
        'podman inspect $_kContainerName > /dev/null 2>&1',
      );
      if (podmanExists == 0) {
        _runtime = 'podman';
        _method = _InstallMethod.container;
        setState(() => _agentState = _AgentState.stopped);
        return;
      }

      // Check binary install
      final binaryExists = await _sshExitCode(
        client,
        'test -f $_kAgentInstallPath',
      );
      if (binaryExists == 0) {
        _method = _InstallMethod.binary;
        final serviceActive = await _sshExitCode(
          client,
          'sudo systemctl is-active orbital-agent > /dev/null 2>&1',
        );
        setState(
          () => _agentState = serviceActive == 0
              ? _AgentState.running
              : _AgentState.stopped,
        );
        return;
      }

      setState(() => _agentState = _AgentState.notInstalled);
    } catch (_) {
      setState(() => _agentState = _AgentState.notInstalled);
    } finally {
      client?.close();
    }
  }

  // ── Install ───────────────────────────────────────────────────────────────

  Future<void> _install() async {
    setState(() {
      _agentState = _AgentState.installing;
      _failed = false;
      _resetSteps();
      _method = _InstallMethod.unknown;
      _runtime = null;
    });

    SSHClient? client;
    try {
      await _runStep(0, () async {
        client = await _connect();
      });

      late String binaryName;
      await _runStep(1, () async {
        final arch = (await _ssh(client!, 'uname -m')).trim();
        binaryName = arch.contains('x86_64')
            ? 'orbital-agent-linux-amd64'
            : 'orbital-agent-linux-arm64';
        setState(() => _steps[1].detail = arch);
      });

      await _runStep(2, () async {
        final dockerCheck = await _sshExitCode(
          client!,
          'docker info > /dev/null 2>&1',
        );
        if (dockerCheck == 0) {
          _runtime = 'docker';
          _method = _InstallMethod.container;
          setState(() => _steps[2].detail = 'Docker found');
          return;
        }
        final podmanCheck = await _sshExitCode(
          client!,
          'podman info > /dev/null 2>&1',
        );
        if (podmanCheck == 0) {
          _runtime = 'podman';
          _method = _InstallMethod.container;
          setState(() => _steps[2].detail = 'Podman found');
          return;
        }
        _method = _InstallMethod.binary;
        setState(() => _steps[2].detail = 'No runtime — using binary');
      });

      final settings = ref.read(settingsRepositoryProvider).load();
      final appThresholds = AlertThresholdProfile(
        cpu: settings.cpuAlertThreshold,
        memory: settings.memoryAlertThreshold,
        disk: settings.diskAlertThreshold,
      );
      final effectiveThresholds = AlertThresholdProfile.effectiveForServer(
        widget.server,
        appThresholds,
      );
      final serverId = widget.server.relayServerId;
      final serverName = widget.server.displayName;
      final relayUrl = '${settings.relayUrl}/alert';
      final authToken = settings.relayAuthToken;
      final cpuThreshold = effectiveThresholds.cpu.toStringAsFixed(0);
      final ramThreshold = effectiveThresholds.memory.toStringAsFixed(0);
      final diskThreshold = effectiveThresholds.disk.toStringAsFixed(0);

      if (_method == _InstallMethod.container) {
        await _runStep(3, () async {
          setState(() => _steps[3].detail = 'Pulling $_kContainerImage...');
          await _ssh(client!, 'sudo $_runtime pull $_kContainerImage');
        });

        await _runStep(4, () async {
          setState(() => _steps[4].detail = 'Configured via environment');
        });

        await _runStep(5, () async {
          await _ssh(
            client!,
            'sudo $_runtime rm -f $_kContainerName 2>/dev/null || true',
          );
          await _ssh(
            client!,
            'sudo $_runtime run -d '
            '--pid=host '
            '--restart=always '
            '--name $_kContainerName '
            '-e SERVER_ID="$serverId" '
            '-e SERVER_NAME="$serverName" '
            '-e RELAY_URL="$relayUrl" '
            '-e AUTH_TOKEN="$authToken" '
            '-e CPU_THRESHOLD="$cpuThreshold" '
            '-e RAM_THRESHOLD="$ramThreshold" '
            '-e DISK_THRESHOLD="$diskThreshold" '
            '$_kContainerImage',
          );
        });

        await _runStep(6, () async {
          await Future.delayed(const Duration(seconds: 3));
          final status = (await _ssh(
            client!,
            'sudo $_runtime inspect -f "{{.State.Status}}" $_kContainerName',
          )).trim();
          if (status != 'running') throw Exception('Container status: $status');
          setState(() => _steps[6].detail = 'Container running');
        });
      } else {
        await _runStep(3, () async {
          final sftp = await client!.sftp();

          try {
            if (!_kPreferSourceBuild) throw Exception('source build disabled');
            setState(
              () => _steps[3].detail =
                  'Downloading current source ($_kAgentSourceRef)...',
            );
            final sourceUrl =
                'https://codeload.github.com/$_kGithubOwner/$_kGithubRepo/tar.gz/refs/heads/$_kAgentSourceRef';
            final sourceResponse = await http.get(Uri.parse(sourceUrl));
            if (sourceResponse.statusCode != 200) {
              throw Exception(
                'Source download failed: HTTP ${sourceResponse.statusCode}',
              );
            }

            const sourceTarPath = '/tmp/orbital-src.tar.gz';
            final sourceTar = await sftp.open(
              sourceTarPath,
              mode:
                  SftpFileOpenMode.create |
                  SftpFileOpenMode.write |
                  SftpFileOpenMode.truncate,
            );
            await sourceTar.write(Stream.value(sourceResponse.bodyBytes));
            await sourceTar.close();

            await _ssh(client!, 'rm -rf /tmp/orbital-src');
            await _ssh(client!, 'mkdir -p /tmp/orbital-src');
            await _ssh(
              client!,
              'tar -xzf $sourceTarPath -C /tmp/orbital-src --strip-components=1',
            );
            await _ssh(
              client!,
              'cd /tmp/orbital-src/agent && CGO_ENABLED=0 go build -o /tmp/orbital-agent',
            );
            await _ssh(client!, 'sudo mv /tmp/orbital-agent $_kAgentInstallPath');
            await _ssh(client!, 'sudo chmod +x $_kAgentInstallPath');
            setState(() => _steps[3].detail = 'Built from source');
          } catch (_) {
            setState(
              () => _steps[3].detail =
                  'Source build unavailable — downloading release binary',
            );
            final releaseUrl =
                'https://github.com/$_kGithubOwner/$_kGithubRepo/releases/latest/download/$binaryName';
            final releaseResponse = await http.get(Uri.parse(releaseUrl));
            if (releaseResponse.statusCode != 200) {
              throw Exception(
                'Release download failed: HTTP ${releaseResponse.statusCode}',
              );
            }
            const tmpPath = '/tmp/orbital-agent';
            final binaryFile = await sftp.open(
              tmpPath,
              mode:
                  SftpFileOpenMode.create |
                  SftpFileOpenMode.write |
                  SftpFileOpenMode.truncate,
            );
            await binaryFile.write(Stream.value(releaseResponse.bodyBytes));
            await binaryFile.close();
            await _ssh(client!, 'sudo mv $tmpPath $_kAgentInstallPath');
            await _ssh(client!, 'sudo chmod +x $_kAgentInstallPath');
          }
        });

        await _runStep(4, () async {
          final config =
              '{"server_id":"$serverId","server_name":"$serverName","relay_url":"$relayUrl","auth_token":"$authToken",'
              '"poll_interval_seconds":30,"cooldown_minutes":5,"thresholds":{'
              '"cpu_percent":$cpuThreshold,"ram_percent":$ramThreshold,"disk_percent":$diskThreshold}}';
          await _ssh(client!, 'sudo mkdir -p $_kAgentConfigDir');
          await _ssh(
            client!,
            "printf '%s' '${config.replaceAll("'", "'\\''")}' | sudo tee $_kAgentConfigPath > /dev/null",
          );
        });

        await _runStep(5, () async {
          const service =
              '[Unit]\nDescription=Orbital Agent\nAfter=network.target\n\n'
              '[Service]\nType=simple\nUser=nobody\n'
              'ExecStart=$_kAgentInstallPath -config $_kAgentConfigPath\n'
              'Restart=on-failure\nRestartSec=10s\n\n[Install]\nWantedBy=multi-user.target\n';
          await _ssh(
            client!,
            "printf '%s' '${service.replaceAll("'", "'\\''")}' | sudo tee $_kServicePath > /dev/null",
          );
          await _ssh(client!, 'sudo systemctl daemon-reload');
          await _ssh(client!, 'sudo systemctl enable orbital-agent');
          await _ssh(client!, 'sudo systemctl restart orbital-agent');
        });

        await _runStep(6, () async {
          await Future.delayed(const Duration(seconds: 2));
          final status = (await _ssh(
            client!,
            'sudo systemctl is-active orbital-agent',
          )).trim();
          if (status != 'active') throw Exception('Service status: $status');
          setState(() => _steps[6].detail = 'Service active');
        });
      }

      setState(() => _agentState = _AgentState.running);
    } catch (_) {
      setState(() => _failed = true);
    } finally {
      client?.close();
    }
  }

  // ── Uninstall ─────────────────────────────────────────────────────────────

  Future<void> _uninstall() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Uninstall Agent?'),
        content: Text(
          'This will remove the orbital-agent from ${widget.server.displayName}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Uninstall',
              style: TextStyle(color: OrbitalColors.danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _agentState = _AgentState.uninstalling);
    SSHClient? client;
    try {
      client = await _connect();

      if (_method == _InstallMethod.container && _runtime != null) {
        await _ssh(
          client,
          'sudo $_runtime stop $_kContainerName 2>/dev/null || true',
        );
        await _ssh(
          client,
          'sudo $_runtime rm -f $_kContainerName 2>/dev/null || true',
        );
      } else {
        await _ssh(
          client,
          'sudo systemctl stop orbital-agent 2>/dev/null || true',
        );
        await _ssh(
          client,
          'sudo systemctl disable orbital-agent 2>/dev/null || true',
        );
        await _ssh(client, 'sudo rm -f $_kServicePath');
        await _ssh(client, 'sudo rm -f $_kAgentInstallPath');
        await _ssh(client, 'sudo rm -rf $_kAgentConfigDir');
        await _ssh(client, 'sudo systemctl daemon-reload');
      }

      setState(() {
        _agentState = _AgentState.notInstalled;
        _method = _InstallMethod.unknown;
        _runtime = null;
      });
    } catch (_) {
      setState(() => _agentState = _AgentState.stopped);
    } finally {
      client?.close();
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<SSHClient> _connect() async {
    final repo = ref.read(serverRepositoryProvider);
    final credential =
        await repo.getCredential(widget.server.credentialStorageKey) ?? '';
    final socket = await SSHSocket.connect(
      widget.server.host,
      widget.server.port,
      timeout: const Duration(seconds: 15),
    );
    final client = SSHClient(
      socket,
      username: widget.server.username,
      onPasswordRequest: widget.server.authTypeEnum == AuthType.password
          ? () => credential
          : null,
      identities: widget.server.authTypeEnum == AuthType.privateKey
          ? [...SSHKeyPair.fromPem(credential)]
          : null,
    );
    await client.authenticated;
    return client;
  }

  Future<void> _runStep(int index, Future<void> Function() action) async {
    setState(() => _steps[index].status = _StepStatus.running);
    try {
      await action();
      setState(() => _steps[index].status = _StepStatus.done);
    } catch (e) {
      setState(() {
        _steps[index].status = _StepStatus.failed;
        _steps[index].detail = e.toString();
        _failed = true;
      });
      rethrow;
    }
  }

  Future<String> _ssh(SSHClient client, String command) async {
    final session = await client.execute(command);
    final bytes = await session.stdout.toList();
    await session.done;
    return utf8.decode(bytes.expand((x) => x).toList());
  }

  Future<int> _sshExitCode(SSHClient client, String command) async {
    final session = await client.execute(command);
    await session.stdout.drain();
    await session.done;
    return session.exitCode ?? 1;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Theme.of(context).dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.sensors_rounded,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Install Agent',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      widget.server.displayName,
                      style: const TextStyle(
                        fontSize: 13,
                        color: OrbitalColors.textMuted,
                        fontFamily: 'Menlo',
                      ),
                    ),
                  ],
                ),
              ),
              if (_method != _InstallMethod.unknown)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: OrbitalColors.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _method == _InstallMethod.container
                        ? _runtime ?? 'container'
                        : 'binary',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: OrbitalColors.accent,
                      fontFamily: 'Menlo',
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 24),

          // Body
          if (_agentState == _AgentState.checking)
            _buildChecking()
          else if (_agentState == _AgentState.notInstalled)
            _buildNotInstalled()
          else if (_agentState == _AgentState.running ||
              _agentState == _AgentState.stopped)
            _buildStatus()
          else if (_agentState == _AgentState.installing)
            _buildInstalling()
          else if (_agentState == _AgentState.uninstalling)
            _buildUninstalling(),
        ],
      ),
    );
  }

  Widget _buildChecking() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              color: OrbitalColors.accent,
              strokeWidth: 2,
            ),
            SizedBox(height: 16),
            Text(
              'Checking agent status...',
              style: TextStyle(color: OrbitalColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotInstalled() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: OrbitalColors.textMuted.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            children: [
              Icon(
                Icons.sensors_off_rounded,
                color: OrbitalColors.textMuted,
                size: 20,
              ),
              SizedBox(width: 12),
              Text(
                'Agent not installed',
                style: TextStyle(color: OrbitalColors.textMuted, fontSize: 14),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildButton(
          label: 'Install',
          icon: Icons.download_rounded,
          color: OrbitalColors.accent,
          onTap: _install,
        ),
      ],
    );
  }

  Widget _buildStatus() {
    final isRunning = _agentState == _AgentState.running;
    final statusColor = isRunning
        ? OrbitalColors.online
        : OrbitalColors.warning;
    final statusLabel = isRunning ? 'Agent running' : 'Agent stopped';
    final statusIcon = isRunning
        ? Icons.sensors_rounded
        : Icons.sensors_off_rounded;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: statusColor.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              Icon(statusIcon, color: statusColor, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      statusLabel,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (_method != _InstallMethod.unknown)
                      Text(
                        _method == _InstallMethod.container
                            ? 'Running via $_runtime'
                            : 'Running as systemd service',
                        style: const TextStyle(
                          color: OrbitalColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildButton(
                label: 'Reinstall',
                icon: Icons.refresh_rounded,
                color: OrbitalColors.accent,
                onTap: _install,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildButton(
                label: 'Uninstall',
                icon: Icons.delete_rounded,
                color: OrbitalColors.danger,
                onTap: _uninstall,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInstalling() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ..._steps.map((step) => _StepRow(step: step)),
        const SizedBox(height: 16),
        if (_failed)
          _buildButton(
            label: 'Retry',
            icon: Icons.refresh_rounded,
            color: OrbitalColors.danger,
            onTap: _install,
          )
        else if (_agentState == _AgentState.running)
          _buildButton(
            label: 'Done',
            icon: Icons.check_rounded,
            color: OrbitalColors.online,
            onTap: () => Navigator.of(context).pop(),
          )
        else
          const Center(
            child: CircularProgressIndicator(
              color: OrbitalColors.accent,
              strokeWidth: 2,
            ),
          ),
      ],
    );
  }

  Widget _buildUninstalling() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              color: OrbitalColors.danger,
              strokeWidth: 2,
            ),
            SizedBox(height: 16),
            Text(
              'Uninstalling agent...',
              style: TextStyle(color: OrbitalColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

// ── _StepRow ──────────────────────────────────────────────────────────────────

class _StepRow extends StatelessWidget {
  final _Step step;
  const _StepRow({required this.step});

  @override
  Widget build(BuildContext context) {
    final color = switch (step.status) {
      _StepStatus.pending => OrbitalColors.textMuted,
      _StepStatus.running => OrbitalColors.accent,
      _StepStatus.done => OrbitalColors.online,
      _StepStatus.failed => OrbitalColors.danger,
      _StepStatus.skipped => OrbitalColors.textMuted,
    };
    final icon = switch (step.status) {
      _StepStatus.pending => Icons.radio_button_unchecked_rounded,
      _StepStatus.running => Icons.circle_outlined,
      _StepStatus.done => Icons.check_circle_rounded,
      _StepStatus.failed => Icons.error_rounded,
      _StepStatus.skipped => Icons.remove_circle_outline_rounded,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          step.status == _StepStatus.running
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color,
                  ),
                )
              : Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: step.status == _StepStatus.pending
                        ? OrbitalColors.textMuted
                        : Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                if (step.detail != null)
                  Text(
                    step.detail!,
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'Menlo',
                      color: step.status == _StepStatus.failed
                          ? OrbitalColors.danger
                          : OrbitalColors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
