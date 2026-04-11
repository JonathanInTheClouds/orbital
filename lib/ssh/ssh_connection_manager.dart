import 'dart:async';
import 'dart:convert';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/logging/orbital_logger.dart';
import '../data/database/app_database.dart';
import '../data/models/server_model.dart';
import '../data/repositories/server_repository.dart';
import '../data/settings/settings_repository.dart';
import 'metrics_parser.dart';
import 'ssh_credential.dart';
import 'ssh_key_service.dart';
import 'ssh_models.dart';

// ── SshConnection ─────────────────────────────────────────────────────────────

/// Manages a single SSH connection to one server.
class SshConnection {
  final Server server;
  final SshCredential credential;
  final SettingsRepository _settings;
  final SshKeyService _keyService;

  SSHClient? _client;
  Timer? _pollTimer;
  ServerMetrics? _lastMetrics;
  Future<void>? _connectOperation;

  final _stateController = StreamController<ServerConnectionState>.broadcast();

  Stream<ServerConnectionState> get stateStream => _stateController.stream;
  ServerConnectionState _state = ServerConnectionState.disconnected;

  ServerConnectionState get currentState => _state;

  String get _tag => '${server.displayName} (${server.host}:${server.port})';

  SshConnection({
    required this.server,
    required this.credential,
    required SettingsRepository settings,
    required SshKeyService keyService,
  }) : _settings = settings,
       _keyService = keyService;

  void _emit(ServerConnectionState state) {
    _state = state;
    if (!_stateController.isClosed) _stateController.add(state);
  }

  bool get _hasLiveClient => _client != null && !_client!.isClosed;

  bool _isRecoverableConnectionError(Object error) {
    if (error is SSHStateError) return true;
    final message = error.toString();
    return message.contains(
          'Connection closed while waiting for channel open',
        ) ||
        message.contains('Transport is closed');
  }

  void _disposeClient() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _client?.close();
    _client = null;
  }

  Future<void> _reconnect() async {
    _disposeClient();
    await connect(forceReconnect: true);
  }

  // ── Connect ───────────────────────────────────────────────────────────────

  Future<void> connect({bool forceReconnect = false}) async {
    if (_connectOperation != null) {
      await _connectOperation;
      return;
    }

    if (!forceReconnect && _state.isConnected && _hasLiveClient) return;
    if (!forceReconnect && _state.isConnecting) return;

    final operation = _connectInternal(forceReconnect: forceReconnect);
    _connectOperation = operation;
    try {
      await operation;
    } finally {
      if (identical(_connectOperation, operation)) {
        _connectOperation = null;
      }
    }
  }

  Future<void> _connectInternal({required bool forceReconnect}) async {
    if (forceReconnect || !_hasLiveClient) {
      _disposeClient();
    }

    _emit(
      ServerConnectionState(
        status: ConnectionStatus.connecting,
        metrics: _lastMetrics,
      ),
    );

    final log = OrbitalLogger.instance;
    log.info('SSH', 'Connecting to $_tag');

    final stopwatch = Stopwatch()..start();

    try {
      final socket = await SSHSocket.connect(
        server.host,
        server.port,
        timeout: Duration(seconds: _settings.load().connectTimeoutSeconds),
      );

      log.debug('SSH', 'Socket established to $_tag — authenticating');

      _client = _keyService.createClient(
        socket: socket,
        username: server.username,
        credential: credential,
      );

      await _client!.authenticated;
      stopwatch.stop();

      log.info(
        'SSH',
        'Connected to $_tag in ${stopwatch.elapsedMilliseconds}ms '
            '(user: ${server.username})',
      );

      // Detect OS — run uname before emitting connected so the detail
      // screen knows immediately whether metrics are supported.
      final osName = (await _runCommand(
        'uname -s',
        allowReconnect: false,
      )).trim();
      log.info('SSH', 'Remote OS for $_tag: $osName');

      if (osName != 'Linux') {
        log.warning(
          'SSH',
          '$_tag runs $osName — metrics not supported, skipping polling',
        );
        _emit(
          _state.copyWith(
            status: ConnectionStatus.unsupportedPlatform,
            connectedAt: DateTime.now(),
            osName: osName,
          ),
        );
        // Don't start polling — terminal and Docker still work fine.
        return;
      }

      _emit(
        _state.copyWith(
          status: ConnectionStatus.connected,
          connectedAt: DateTime.now(),
          osName: osName,
        ),
      );

      _startPolling();
    } on SSHAuthError catch (e) {
      stopwatch.stop();
      _disposeClient();
      log.error('SSH', 'Auth failed for $_tag: ${e.message}');
      _emit(
        ServerConnectionState(
          status: ConnectionStatus.error,
          metrics: _lastMetrics,
          errorMessage: 'Authentication failed: ${e.message}',
        ),
      );
    } catch (e) {
      stopwatch.stop();
      _disposeClient();
      log.error('SSH', 'Connection error for $_tag: $e');
      _emit(
        ServerConnectionState(
          status: ConnectionStatus.error,
          metrics: _lastMetrics,
          errorMessage: e.toString(),
        ),
      );
    }
  }

  // ── Polling ───────────────────────────────────────────────────────────────

  void _startPolling() {
    OrbitalLogger.instance.debug('SSH', 'Started metric polling for $_tag');
    _fetchMetrics();
    _pollTimer = Timer.periodic(
      Duration(seconds: _settings.load().pollIntervalSeconds),
      (_) => _fetchMetrics(),
    );
  }

  Future<void> _fetchMetrics() async {
    if (!_state.isConnected && !_state.isConnecting) return;

    try {
      final result = await _runCommand(MetricsParser.metricsScript);
      final metrics = MetricsParser.parse(result, _lastMetrics);
      if (metrics != null) {
        _lastMetrics = metrics;
        _emit(
          _state.copyWith(status: ConnectionStatus.connected, metrics: metrics),
        );
      } else {
        OrbitalLogger.instance.warning(
          'SSH',
          'Metrics parse returned null for $_tag',
        );
      }
    } catch (e) {
      OrbitalLogger.instance.error('SSH', 'Lost connection to $_tag: $e');
      _disposeClient();
      _emit(
        ServerConnectionState(
          status: ConnectionStatus.error,
          metrics: _lastMetrics,
          errorMessage: 'Lost connection: ${e.toString()}',
        ),
      );
    }
  }

  // ── Commands ──────────────────────────────────────────────────────────────

  Future<String> _runCommand(
    String command, {
    bool allowReconnect = true,
  }) async {
    // Abbreviate the metrics script in logs — it's hundreds of lines and
    // would flood the log. Everything else is shown in full.
    final label = command == MetricsParser.metricsScript
        ? '<metrics-script>'
        : command.length > 80
        ? '${command.substring(0, 80)}…'
        : command;

    final sw = Stopwatch()..start();
    OrbitalLogger.instance.debug('CMD', '[$_tag] → $label');

    try {
      if (allowReconnect) {
        await connect(forceReconnect: !_hasLiveClient || !_state.isConnected);
      }
      if (!_hasLiveClient) {
        throw StateError('SSH client is unavailable');
      }

      final session = await _client!.execute(command);
      final chunks = <int>[];
      await for (final chunk in session.stdout) {
        chunks.addAll(chunk);
      }
      await session.done;
      sw.stop();

      OrbitalLogger.instance.debug(
        'CMD',
        '[$_tag] ← $label  ${sw.elapsedMilliseconds}ms  ${chunks.length}B',
      );

      return utf8.decode(chunks, allowMalformed: true);
    } catch (e) {
      if (allowReconnect && _isRecoverableConnectionError(e)) {
        sw.stop();
        OrbitalLogger.instance.warning(
          'SSH',
          'Recovering closed SSH transport for $_tag during $label',
        );
        await _reconnect();
        return _runCommand(command, allowReconnect: false);
      }

      sw.stop();
      OrbitalLogger.instance.error(
        'CMD',
        '[$_tag] ✗ $label  ${sw.elapsedMilliseconds}ms  error: $e',
      );
      rethrow;
    }
  }

  /// Run an arbitrary command and return stdout.
  Future<String> execute(String command) async {
    return _runCommand(command);
  }

  /// Open an interactive shell session.
  Future<SSHSession> openShell({
    required int width,
    required int height,
  }) async {
    Future<SSHSession> open() async {
      await connect(forceReconnect: !_hasLiveClient || !_state.isConnected);
      if (!_hasLiveClient || !_state.isConnected) {
        throw StateError('Not connected');
      }
      OrbitalLogger.instance.info(
        'SSH',
        'Opening shell on $_tag (${width}x$height)',
      );
      return _client!.shell(
        pty: SSHPtyConfig(type: 'xterm-256color', width: width, height: height),
      );
    }

    try {
      return await open();
    } catch (e) {
      if (_isRecoverableConnectionError(e)) {
        OrbitalLogger.instance.warning(
          'SSH',
          'Recovering closed SSH transport for $_tag while opening shell',
        );
        await _reconnect();
        return open();
      }
      rethrow;
    }
  }

  // ── Disconnect ────────────────────────────────────────────────────────────

  Future<void> disconnect() async {
    OrbitalLogger.instance.info('SSH', 'Disconnecting from $_tag');
    _disposeClient();
    _emit(ServerConnectionState.disconnected);
  }

  void dispose() {
    _disposeClient();
    _stateController.close();
  }
}

// ── SshConnectionManager ──────────────────────────────────────────────────────

/// Manages connections to all servers.
class SshConnectionManager {
  final Map<int, SshConnection> _connections = {};
  final ServerRepository _repo;
  final SettingsRepository _settings;
  final SshKeyService _keyService;

  SshConnectionManager(this._repo, this._settings, this._keyService);

  Future<SshConnection> getOrConnect(Server server) async {
    if (_connections.containsKey(server.id)) {
      final conn = _connections[server.id]!;
      OrbitalLogger.instance.debug(
        'SSH',
        'Reusing existing connection for ${server.displayName}',
      );
      await conn.connect();
      return conn;
    }

    final credential = await _repo.getCredentialForServer(server);
    if (credential == null) {
      OrbitalLogger.instance.error(
        'SSH',
        'No credential found for ${server.displayName}',
      );
      throw StateError('No credential found for server');
    }

    OrbitalLogger.instance.debug(
      'SSH',
      'Creating new connection for ${server.displayName}',
    );

    final conn = SshConnection(
      server: server,
      credential: credential,
      settings: _settings,
      keyService: _keyService,
    );
    _connections[server.id] = conn;
    await conn.connect();
    return conn;
  }

  SshConnection? getConnection(int serverId) => _connections[serverId];

  Future<void> disconnect(int serverId) async {
    await _connections[serverId]?.disconnect();
    _connections.remove(serverId);
  }

  void dispose() {
    OrbitalLogger.instance.info('SSH', 'Disposing all connections');
    for (final conn in _connections.values) {
      conn.dispose();
    }
    _connections.clear();
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

final sshManagerProvider = Provider<SshConnectionManager>((ref) {
  final manager = SshConnectionManager(
    ref.watch(serverRepositoryProvider),
    ref.watch(settingsRepositoryProvider),
    ref.watch(sshKeyServiceProvider),
  );
  ref.onDispose(manager.dispose);
  return manager;
});

final serverConnectionProvider =
    StreamProvider.family<ServerConnectionState, Server>((ref, server) async* {
      final manager = ref.watch(sshManagerProvider);

      yield ServerConnectionState.disconnected;

      final conn = await manager.getOrConnect(server);

      // Yield the current state immediately — connect() may have already
      // emitted unsupportedPlatform or error before we subscribed to the stream.
      yield conn.currentState;

      yield* conn.stateStream;
    });
