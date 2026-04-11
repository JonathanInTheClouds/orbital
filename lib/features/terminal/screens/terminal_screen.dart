import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:xterm/xterm.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/server_model.dart';
import '../../../data/repositories/server_repository.dart';
import '../../../ssh/ssh_connection_manager.dart';
import '../session_log_manager.dart';

// ── TerminalScreen ────────────────────────────────────────────────────────────

class TerminalScreen extends ConsumerStatefulWidget {
  final String serverId;

  const TerminalScreen({super.key, required this.serverId});

  @override
  ConsumerState<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends ConsumerState<TerminalScreen> {
  final _terminal = Terminal(maxLines: 10000);
  final _terminalController = TerminalController();

  SSHSession? _session;
  StreamSubscription? _stdoutSub;
  StreamSubscription? _stderrSub;

  _TerminalState _state = _TerminalState.connecting;
  String? _errorMessage;
  SessionLogManager? _sessionLog;
  bool _sessionSaved = false;

  // Track current PTY dimensions to avoid redundant resizes.
  int _currentCols = 80;
  int _currentRows = 24;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void dispose() {
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
    _session?.close();
    _sessionLog?.stop();
    _terminalController.dispose();
    super.dispose();
  }

  // ── SSH shell ─────────────────────────────────────────────────────────────

  Future<void> _connect() async {
    try {
      final id = int.parse(widget.serverId);
      final manager = ref.read(sshManagerProvider);

      SshConnection conn;
      final existing = manager.getConnection(id);
      if (existing != null && existing.currentState.isConnected) {
        conn = existing;
      } else {
        final server = await ref
            .read(serverRepositoryProvider)
            .getServerById(id);
        if (server == null) throw StateError('Server not found');
        conn = await manager.getOrConnect(server);
      }

      final session = await conn.openShell(
        width: _currentCols,
        height: _currentRows,
      );
      _session = session;

      // Start session recording.
      _sessionLog = SessionLogManager(serverName: conn.server.displayName);
      await _sessionLog!.start();

      // Wire xterm → SSH (user input)
      _terminal.onOutput = (data) {
        _session?.write(utf8.encode(data));
      };

      // Wire SSH → xterm (output) + session log
      _stdoutSub = session.stdout.listen((data) {
        _terminal.write(utf8.decode(data, allowMalformed: true));
        _sessionLog?.write(data);
      });

      _stderrSub = session.stderr.listen((data) {
        _terminal.write(utf8.decode(data, allowMalformed: true));
        _sessionLog?.write(data);
      });

      // Handle session close
      session.done.then((_) async {
        await _sessionLog?.stop();
        if (mounted) {
          setState(() {
            _state = _TerminalState.closed;
            _sessionSaved = true;
          });
        }
      });

      if (mounted) setState(() => _state = _TerminalState.connected);
    } catch (e) {
      if (mounted) {
        setState(() {
          _state = _TerminalState.error;
          _errorMessage = e.toString();
        });
      }
    }
  }

  void _resizePty(int cols, int rows) {
    if (cols == _currentCols && rows == _currentRows) return;
    _currentCols = cols;
    _currentRows = rows;
    _session?.resizeTerminal(cols, rows);
  }

  // ── Toolbar helpers ───────────────────────────────────────────────────────

  void _sendControlChar(String char) {
    final code = switch (char) {
      'C' => 0x03,
      'D' => 0x04,
      'Z' => 0x1A,
      'L' => 0x0C,
      _ => 0x09,
    };
    _session?.write(Uint8List.fromList([code]));
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      _session?.write(utf8.encode(data!.text!));
    }
  }

  Future<void> _saveSession() async {
    await _sessionLog?.stop();
    if (mounted) setState(() => _sessionSaved = true);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          Expanded(child: _buildBody()),
          _buildToolbar(isDark),
        ],
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
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
      title: Row(
        children: [
          Icon(
            Icons.terminal_rounded,
            size: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Text(
            'Terminal',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
      actions: [
        Container(
          margin: const EdgeInsets.only(right: 16),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            color: _statusColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _statusColor.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_state == _TerminalState.connecting)
                SizedBox(
                  width: 7,
                  height: 7,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: _statusColor,
                  ),
                )
              else
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: _statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
              const SizedBox(width: 5),
              Text(
                _statusLabel,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: _statusColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Color get _statusColor => switch (_state) {
    _TerminalState.connected => OrbitalColors.online,
    _TerminalState.connecting => OrbitalColors.warning,
    _TerminalState.closed => OrbitalColors.offline,
    _TerminalState.error => OrbitalColors.danger,
  };

  String get _statusLabel => switch (_state) {
    _TerminalState.connected => 'Connected',
    _TerminalState.connecting => 'Connecting',
    _TerminalState.closed => 'Closed',
    _TerminalState.error => 'Error',
  };

  Widget _buildBody() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final enableDeleteDetection = switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.android => true,
      _ => false,
    };
    return switch (_state) {
      _TerminalState.connecting => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              color: Theme.of(context).colorScheme.primary,
              strokeWidth: 2,
            ),
            const SizedBox(height: 16),
            const Text(
              'Opening shell…',
              style: TextStyle(fontSize: 14, color: OrbitalColors.textMuted),
            ),
          ],
        ),
      ),
      _TerminalState.error => Center(
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
                _errorMessage ?? 'Unknown error',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: OrbitalColors.textMuted,
                  fontFamily: 'Menlo',
                ),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _state = _TerminalState.connecting;
                    _errorMessage = null;
                  });
                  _connect();
                },
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retry'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.primary,
                  side: BorderSide(color: Theme.of(context).colorScheme.primary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      _TerminalState.closed => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.power_settings_new_rounded,
              size: 48,
              color: OrbitalColors.textMuted,
            ),
            const SizedBox(height: 16),
            const Text(
              'Session closed',
              style: TextStyle(fontSize: 16, color: OrbitalColors.textMuted),
            ),
            const SizedBox(height: 8),
            if (_sessionSaved)
              const Text(
                'Session log saved',
                style: TextStyle(fontSize: 13, color: OrbitalColors.online),
              ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _state = _TerminalState.connecting;
                  _sessionSaved = false;
                });
                _connect();
              },
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Reconnect'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.primary,
                side: BorderSide(color: Theme.of(context).colorScheme.primary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
      _TerminalState.connected => LayoutBuilder(
        builder: (context, constraints) {
          const charWidth = 8.0;
          const charHeight = 16.0;
          final cols = (constraints.maxWidth / charWidth).floor().clamp(
            20,
            500,
          );
          final rows = (constraints.maxHeight / charHeight).floor().clamp(
            5,
            200,
          );
          _resizePty(cols, rows);

          return TerminalView(
            _terminal,
            controller: _terminalController,
            theme: isDark
                ? _orbitalTerminalThemeDark
                : _orbitalTerminalThemeLight,
            textStyle: const TerminalStyle(fontSize: 13, fontFamily: 'Menlo'),
            autofocus: true,
            deleteDetection: enableDeleteDetection,
            backgroundOpacity: 1,
            padding: const EdgeInsets.all(4),
          );
        },
      ),
    };
  }

  // ── Toolbar ───────────────────────────────────────────────────────────────

  Widget _buildToolbar(bool isDark) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: EdgeInsets.only(
        left: 8,
        right: 8,
        top: 6,
        bottom: MediaQuery.of(context).padding.bottom + 6,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _ToolbarButton(label: 'Tab', onTap: () => _sendControlChar('Tab')),
            _ToolbarButton(
              label: 'Ctrl+C',
              onTap: () => _sendControlChar('C'),
              color: OrbitalColors.danger,
            ),
            _ToolbarButton(label: 'Ctrl+D', onTap: () => _sendControlChar('D')),
            _ToolbarButton(label: 'Ctrl+Z', onTap: () => _sendControlChar('Z')),
            _ToolbarButton(label: 'Ctrl+L', onTap: () => _sendControlChar('L')),
            _ToolbarButton(
              label: 'Paste',
              icon: Icons.content_paste_rounded,
              onTap: _paste,
            ),
            _ToolbarButton(
              label: _sessionSaved ? 'Saved ✓' : 'Save Log',
              icon: _sessionSaved
                  ? Icons.check_circle_rounded
                  : Icons.save_alt_rounded,
              color: _sessionSaved
                  ? OrbitalColors.online
                  : Theme.of(context).colorScheme.onSurfaceVariant,
              onTap: _sessionSaved ? null : _saveSession,
            ),
          ],
        ),
      ),
    );
  }
}

// ── _TerminalState ────────────────────────────────────────────────────────────

enum _TerminalState { connecting, connected, closed, error }

// ── _ToolbarButton ────────────────────────────────────────────────────────────

class _ToolbarButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final Color? color;

  const _ToolbarButton({
    required this.label,
    required this.onTap,
    this.icon,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isDark ? OrbitalColors.surfaceElevated : Colors.black.withOpacity(0.04),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isDark
                ? Colors.white.withOpacity(0.08)
                : Colors.black.withOpacity(0.10),
          ),
        ),
        child: icon != null
            ? Icon(icon, size: 15, color: c)
            : Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: c,
                  fontFamily: 'Menlo',
                ),
              ),
      ),
    );
  }
}

// ── Terminal theme ────────────────────────────────────────────────────────────

const _orbitalTerminalThemeDark = TerminalTheme(
  cursor: Color(0xFF3B82F6),
  selection: Color(0x443B82F6),
  foreground: Color(0xFFF1F5F9),
  background: Color(0xFF000000),
  black: Color(0xFF1A2235),
  red: Color(0xFFEF4444),
  green: Color(0xFF22C55E),
  yellow: Color(0xFFF59E0B),
  blue: Color(0xFF3B82F6),
  magenta: Color(0xFF8B5CF6),
  cyan: Color(0xFF06B6D4),
  white: Color(0xFFF1F5F9),
  brightBlack: Color(0xFF475569),
  brightRed: Color(0xFFFCA5A5),
  brightGreen: Color(0xFF86EFAC),
  brightYellow: Color(0xFFFDE68A),
  brightBlue: Color(0xFF93C5FD),
  brightMagenta: Color(0xFFC4B5FD),
  brightCyan: Color(0xFF67E8F9),
  brightWhite: Color(0xFFFFFFFF),
  searchHitBackground: Color(0xFFF59E0B),
  searchHitBackgroundCurrent: Color(0xFF3B82F6),
  searchHitForeground: Color(0xFF000000),
);

const _orbitalTerminalThemeLight = TerminalTheme(
  cursor: Color(0xFF2563EB),
  selection: Color(0x332563EB),
  foreground: Color(0xFF0F172A),
  background: Color(0xFFF8FAFC),
  black: Color(0xFF0F172A),
  red: Color(0xFFDC2626),
  green: Color(0xFF16A34A),
  yellow: Color(0xFFD97706),
  blue: Color(0xFF2563EB),
  magenta: Color(0xFF7C3AED),
  cyan: Color(0xFF0891B2),
  white: Color(0xFFE2E8F0),
  brightBlack: Color(0xFF475569),
  brightRed: Color(0xFFEF4444),
  brightGreen: Color(0xFF22C55E),
  brightYellow: Color(0xFFF59E0B),
  brightBlue: Color(0xFF3B82F6),
  brightMagenta: Color(0xFF8B5CF6),
  brightCyan: Color(0xFF06B6D4),
  brightWhite: Color(0xFFFFFFFF),
  searchHitBackground: Color(0xFFF59E0B),
  searchHitBackgroundCurrent: Color(0xFF2563EB),
  searchHitForeground: Color(0xFFFFFFFF),
);
