import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

// ── Log level ─────────────────────────────────────────────────────────────────

enum LogLevel {
  debug,
  info,
  warning,
  error;

  String get label => switch (this) {
        LogLevel.debug => 'DEBUG',
        LogLevel.info => 'INFO',
        LogLevel.warning => 'WARN',
        LogLevel.error => 'ERROR',
      };

  bool operator >=(LogLevel other) => index >= other.index;
}

// ── LogEntry ──────────────────────────────────────────────────────────────────

class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String tag;
  final String message;

  const LogEntry({
    required this.timestamp,
    required this.level,
    required this.tag,
    required this.message,
  });

  String get formatted {
    final ts = timestamp.toIso8601String().replaceFirst('T', ' ').substring(0, 23);
    return '[$ts] [${level.label.padRight(5)}] [$tag] $message';
  }

  @override
  String toString() => formatted;
}

// ── OrbitalLogger ─────────────────────────────────────────────────────────────

/// App-wide logger. Access via [OrbitalLogger.instance] or the Riverpod
/// [orbitalLoggerProvider].
///
/// - Keeps the last [maxEntries] log entries in memory.
/// - Writes all entries to `orbital_debug.log` in the app documents directory.
/// - Exposes a broadcast [stream] so UI can reactively display new entries.
class OrbitalLogger {
  OrbitalLogger._();

  static final instance = OrbitalLogger._();

  // ── Config ────────────────────────────────────────────────────────────────

  static const maxEntries = 1000;
  static const logFileName = 'orbital_debug.log';

  // ── State ─────────────────────────────────────────────────────────────────

  final List<LogEntry> _entries = [];
  final _controller = StreamController<LogEntry>.broadcast();

  File? _logFile;
  IOSink? _sink;
  bool _initialized = false;

  List<LogEntry> get entries => List.unmodifiable(_entries);
  Stream<LogEntry> get stream => _controller.stream;

  // ── Initialisation ────────────────────────────────────────────────────────

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final dir = await getApplicationDocumentsDirectory();
      _logFile = File('${dir.path}/$logFileName');
      _sink = _logFile!.openWrite(mode: FileMode.append);
      _sink!.writeln('\n─── Orbital session started: ${DateTime.now().toIso8601String()} ───');
    } catch (e) {
      // File logging is best-effort — don't crash if it fails.
    }

    info('OrbitalLogger', 'Logger initialised');
  }

  // ── Logging ───────────────────────────────────────────────────────────────

  void debug(String tag, String message) => _log(LogLevel.debug, tag, message);
  void info(String tag, String message) => _log(LogLevel.info, tag, message);
  void warning(String tag, String message) => _log(LogLevel.warning, tag, message);
  void error(String tag, String message) => _log(LogLevel.error, tag, message);

  void _log(LogLevel level, String tag, String message) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      tag: tag,
      message: message,
    );

    // Ring buffer — evict oldest when full.
    if (_entries.length >= maxEntries) _entries.removeAt(0);
    _entries.add(entry);

    // Broadcast to UI listeners.
    if (!_controller.isClosed) _controller.add(entry);

    // Write to file (best-effort, async).
    _sink?.writeln(entry.formatted);

    // Also echo to console in debug mode.
    assert(() {
      // ignore: avoid_print
      print(entry.formatted);
      return true;
    }());
  }

  // ── File access ───────────────────────────────────────────────────────────

  /// Full path to the log file, or null if not initialised.
  String? get logFilePath => _logFile?.path;

  /// Read the entire log file as a string.
  Future<String> readLogFile() async {
    try {
      await _sink?.flush();
      return await _logFile?.readAsString() ?? '';
    } catch (_) {
      return '';
    }
  }

  /// Delete the log file and clear the in-memory buffer.
  Future<void> clear() async {
    _entries.clear();
    try {
      await _sink?.flush();
      await _sink?.close();
      await _logFile?.writeAsString('');
      _sink = _logFile?.openWrite(mode: FileMode.append);
    } catch (_) {}
    info('OrbitalLogger', 'Log cleared');
  }

  /// All in-memory entries filtered by minimum level.
  List<LogEntry> entriesAtLevel(LogLevel minLevel) =>
      _entries.where((e) => e.level >= minLevel).toList();

  void dispose() {
    _sink?.close();
    _controller.close();
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

final orbitalLoggerProvider = Provider<OrbitalLogger>((ref) {
  final logger = OrbitalLogger.instance;
  ref.onDispose(logger.dispose);
  return logger;
});

/// Stream provider that emits every new [LogEntry] as it arrives.
final logStreamProvider = StreamProvider<LogEntry>((ref) {
  return ref.watch(orbitalLoggerProvider).stream;
});
