import 'dart:io';

import 'package:flutter/services.dart';

/// Platform channel bridge to the iOS Live Activity / Dynamic Island.
///
/// All methods are no-ops on non-iOS platforms so the rest of the app
/// doesn't need to guard every call site.
class DynamicIslandService {
  static const _channel = MethodChannel('com.orbital/dynamic_island');

  static bool get _isIOS => Platform.isIOS;

  /// Returns true if Live Activities are available and enabled by the user.
  static Future<bool> isSupported() async {
    if (!_isIOS) return false;
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Returns true if a Live Activity is currently running.
  static Future<bool> isWatching() async {
    if (!_isIOS) return false;
    try {
      return await _channel.invokeMethod<bool>('isWatching') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Starts a new Live Activity for the given server.
  /// Returns true on success.
  static Future<bool> startWatching({
    required String serverName,
    required String host,
    required double cpu,
    required double ram,
    required double disk,
  }) async {
    if (!_isIOS) return false;
    try {
      return await _channel.invokeMethod<bool>('startWatching', {
            'serverName': serverName,
            'host': host,
            'cpu': cpu,
            'ram': ram,
            'disk': disk,
          }) ??
          false;
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('[DynamicIsland] startWatching failed: $e');
      return false;
    }
  }

  /// Pushes a fresh metrics snapshot to the running Live Activity.
  static Future<void> updateMetrics({
    required String serverName,
    required double cpu,
    required double ram,
    required double disk,
    bool isConnected = true,
  }) async {
    if (!_isIOS) return;
    try {
      await _channel.invokeMethod<void>('updateMetrics', {
        'serverName': serverName,
        'cpu': cpu,
        'ram': ram,
        'disk': disk,
        'isConnected': isConnected,
      });
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('[DynamicIsland] updateMetrics failed: $e');
    }
  }

  /// Ends the running Live Activity and dismisses the island.
  static Future<void> stopWatching() async {
    if (!_isIOS) return;
    try {
      await _channel.invokeMethod<void>('stopWatching');
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('[DynamicIsland] stopWatching failed: $e');
    }
  }
}
