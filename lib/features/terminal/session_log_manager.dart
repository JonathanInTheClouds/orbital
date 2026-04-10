import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../../core/logging/orbital_logger.dart';

// ── SessionLogManager ─────────────────────────────────────────────────────────

/// Records terminal session output to a timestamped file in the app's
/// documents directory under `terminal_logs/`.
///
/// Usage:
/// ```dart
/// final manager = SessionLogManager(serverName: 'prod-web-01');
/// await manager.start();
/// manager.write(bytes);   // call for every stdout/stderr chunk
/// await manager.stop();
/// final path = manager.filePath;
/// ```
class SessionLogManager {
  final String serverName;

  File? _file;
  IOSink? _sink;
  bool _active = false;
  DateTime? _startedAt;

  SessionLogManager({required this.serverName});

  bool get isActive => _active;
  String? get filePath => _file?.path;

  // ── Start ─────────────────────────────────────────────────────────────────

  Future<void> start() async {
    if (_active) return;

    try {
      final dir = await getApplicationDocumentsDirectory();
      final logDir = Directory('${dir.path}/terminal_logs');
      if (!await logDir.exists()) await logDir.create(recursive: true);

      final ts = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-')
          .substring(0, 19); // YYYY-MM-DDTHH-MM-SS

      final safeName = serverName.replaceAll(RegExp(r'[^\w.-]'), '_');
      _file = File('${logDir.path}/${safeName}_$ts.log');
      _sink = _file!.openWrite(mode: FileMode.write);

      _startedAt = DateTime.now();
      _sink!.writeln(
        '─── Session started: ${_startedAt!.toIso8601String()} '
        '│ server: $serverName ───',
      );

      _active = true;

      OrbitalLogger.instance.info(
        'Terminal',
        'Session recording started for $serverName → ${_file!.path}',
      );
    } catch (e) {
      OrbitalLogger.instance.error(
        'Terminal',
        'Failed to start session recording for $serverName: $e',
      );
    }
  }

  // ── Write ─────────────────────────────────────────────────────────────────

  /// Write a chunk of raw terminal bytes to the log file.
  /// Call this for every stdout and stderr emission from the SSH session.
  void write(List<int> bytes) {
    if (!_active || _sink == null) return;
    // Write raw bytes — the file captures the terminal stream as-is,
    // including ANSI escape codes. Useful for replay; strip with `cat` or
    // `ansifilter` if you want plain text.
    _sink!.add(bytes);
  }

  // ── Stop ──────────────────────────────────────────────────────────────────

  Future<void> stop() async {
    if (!_active) return;
    _active = false;

    final duration = _startedAt != null
        ? DateTime.now().difference(_startedAt!)
        : Duration.zero;

    try {
      _sink?.writeln(
        '\n─── Session ended: ${DateTime.now().toIso8601String()} '
        '│ duration: ${_formatDuration(duration)} ───',
      );
      await _sink?.flush();
      await _sink?.close();
      _sink = null;

      OrbitalLogger.instance.info(
        'Terminal',
        'Session recording saved for $serverName '
            '(${_formatDuration(duration)}) → ${_file!.path}',
      );
    } catch (e) {
      OrbitalLogger.instance.error(
        'Terminal',
        'Failed to finalise session log for $serverName: $e',
      );
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String _formatDuration(Duration d) {
    if (d.inHours > 0) {
      return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    }
    if (d.inMinutes > 0) {
      return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
    }
    return '${d.inSeconds}s';
  }

  /// List all saved session log files, newest first.
  static Future<List<File>> listSessions() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final logDir = Directory('${dir.path}/terminal_logs');
      if (!await logDir.exists()) return [];

      final files = await logDir
          .list()
          .where((e) => e is File && e.path.endsWith('.log'))
          .cast<File>()
          .toList();

      files.sort((a, b) => b.path.compareTo(a.path));
      return files;
    } catch (_) {
      return [];
    }
  }
}
