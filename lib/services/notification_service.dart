import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../core/logging/orbital_logger.dart';
import '../data/models/server_model.dart';
import '../data/repositories/server_repository.dart';
import '../data/settings/settings_repository.dart';
import '../features/alerts/models/alert_model.dart';
import '../features/alerts/providers/alert_provider.dart';

// ── Background message handler ────────────────────────────────────────────────
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {}

// ── NotificationService ───────────────────────────────────────────────────────

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final _log = OrbitalLogger.instance;
  final _messaging = FirebaseMessaging.instance;
  final _localNotifications = FlutterLocalNotificationsPlugin();

  static const _channelId = 'orbital_alerts';
  static const _channelName = 'Server Alerts';
  static const _channelDesc = 'Alerts from your Orbital-monitored servers';

  Future<void> init(WidgetRef ref) async {
    await _setupLocalNotifications();
    await _requestPermission();
    _setupMessageHandlers(ref);
    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);
    unawaited(registerWithRelay(ref));
  }

  Future<RelayRegistrationResult> registerWithRelay(WidgetRef ref) async {
    return _registerWithRelay(ref);
  }

  // ── Local notifications ───────────────────────────────────────────────────

  Future<void> _setupLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _localNotifications.initialize(
      settings: const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: _channelDesc,
            importance: Importance.high,
          ),
        );

    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  // ── Permission ────────────────────────────────────────────────────────────

  Future<void> _requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    _log.info('Notifications', 'Permission: ${settings.authorizationStatus}');
  }

  // ── Message handlers ──────────────────────────────────────────────────────

  void _setupMessageHandlers(WidgetRef ref) {
    // Foreground — still record in-app alerts, but only show a local
    // notification on Android. On iOS, FCM foreground presentation options
    // already display system banners, so showing a local notification too
    // causes duplicates.
    FirebaseMessaging.onMessage.listen((message) {
      _log.info('Notifications', 'Foreground: ${message.messageId}');
      _handleMessage(message, ref);
      if (Platform.isAndroid) {
        _showLocalNotification(message);
      }
    });

    // Background tap — app was opened from notification, just record it
    // DO NOT show another local notification — FCM already showed one
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _log.info(
        'Notifications',
        'Opened from notification: ${message.messageId}',
      );
      _handleMessage(message, ref);
      // No _showLocalNotification here
    });
  }

  void _handleMessage(RemoteMessage message, WidgetRef ref) {
    final data = message.data;
    if (data.isEmpty) return;

    try {
      final parsed = _parseAlertPayload(data);
      final alert = AlertModel(
        id: message.messageId ?? DateTime.now().toIso8601String(),
        serverId: parsed.serverId,
        serverName: parsed.serverName,
        metric: parsed.metric,
        value: parsed.value,
        threshold: parsed.threshold,
        timestamp: parsed.timestamp,
      );
      ref.read(alertNotifierProvider.notifier).addAlert(alert);
    } catch (e) {
      _log.error('Notifications', 'Failed to parse alert: $e');
    }
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    await _localNotifications.show(
      id: notification.hashCode,
      title: notification.title,
      body: notification.body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  // ── Relay registration ────────────────────────────────────────────────────

  Future<RelayRegistrationResult> _registerWithRelay(WidgetRef ref) async {
    try {
      final settings = ref.read(settingsRepositoryProvider).load();

      if (settings.relayUrl.isEmpty || settings.relayAuthToken.isEmpty) {
        _log.info(
          'Notifications',
          'Relay not configured — skipping registration',
        );
        return const RelayRegistrationResult(
          success: false,
          message: 'Set relay URL and auth token first.',
        );
      }

      final token = await _messaging.getToken();
      if (token == null) {
        _log.warning('Notifications', 'Could not get FCM token');
        return const RelayRegistrationResult(
          success: false,
          message: 'Could not get FCM token from this device.',
        );
      }

      final apnsToken = await _messaging.getAPNSToken();
      _log.info('Notifications', 'APNs token: ${apnsToken ?? "NULL"}');
      _log.info('Notifications', 'FCM token: ${token.substring(0, 20)}...');

      // Auto-collect all server IDs from the database — no manual entry needed.
      final servers = await ref.read(serverRepositoryProvider).getAllServers();
      final serverIds = servers.map((s) => s.relayServerId).toList();

      if (serverIds.isEmpty) {
        _log.info(
          'Notifications',
          'No servers in database — skipping relay registration',
        );
        return const RelayRegistrationResult(
          success: false,
          message: 'Add a server before registering with relay.',
        );
      }

      _log.info('Notifications', 'Registering for server IDs: $serverIds');

      final platform = Platform.isIOS ? 'ios' : 'android';

      final response = await http
          .post(
            Uri.parse('${settings.relayUrl}/register'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${settings.relayAuthToken}',
            },
            body: jsonEncode({
              'device_token': token,
              'platform': platform,
              'server_ids': serverIds,
            }),
          )
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              _log.warning('Notifications', 'Relay registration timed out');
              return http.Response('timeout', 408);
            },
          );

      if (response.statusCode == 200) {
        _log.info(
          'Notifications',
          'Registered with relay for ${serverIds.length} servers',
        );
        return RelayRegistrationResult(
          success: true,
          message: 'Registered with relay for ${serverIds.length} servers.',
        );
      } else if (response.statusCode != 408) {
        _log.warning(
          'Notifications',
          'Relay registration failed: HTTP ${response.statusCode}',
        );
        return RelayRegistrationResult(
          success: false,
          message: 'Relay registration failed (HTTP ${response.statusCode}).',
        );
      }

      return const RelayRegistrationResult(
        success: false,
        message: 'Relay registration timed out.',
      );
    } catch (e) {
      _log.error('Notifications', 'Relay registration error: $e');
      return RelayRegistrationResult(
        success: false,
        message: 'Relay registration error: $e',
      );
    }
  }
}

class RelayRegistrationResult {
  final bool success;
  final String message;

  const RelayRegistrationResult({required this.success, required this.message});
}

class _ParsedAlertPayload {
  final String serverId;
  final String? serverName;
  final String metric;
  final double value;
  final double threshold;
  final DateTime timestamp;

  const _ParsedAlertPayload({
    required this.serverId,
    required this.serverName,
    required this.metric,
    required this.value,
    required this.threshold,
    required this.timestamp,
  });
}

_ParsedAlertPayload _parseAlertPayload(Map<String, dynamic> data) {
  final title = _readString(data['title']);
  final body = _readString(data['body']);
  final titleMetric = _metricFromTitle(title);
  final titleServerId = _serverIdFromTitle(title);
  final bodyNumbers = _numbersFromText(body);

  return _ParsedAlertPayload(
    serverId: _readString(data['server_id']) ?? titleServerId ?? 'unknown',
    serverName:
        _readString(data['display_name']) ??
        _readString(data['server_name']) ??
        titleServerId,
    metric: _readString(data['metric']) ?? titleMetric ?? 'unknown',
    value: _readDouble(data['value']) ?? bodyNumbers.firstOrNull ?? 0,
    threshold:
        _readDouble(data['threshold']) ??
        (bodyNumbers.length > 1 ? bodyNumbers[1] : 0),
    timestamp: _readString(data['timestamp']) != null
        ? DateTime.tryParse(_readString(data['timestamp'])!) ?? DateTime.now()
        : DateTime.now(),
  );
}

String? _readString(dynamic value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

double? _readDouble(dynamic value) {
  final text = _readString(value);
  if (text == null) return null;
  return double.tryParse(text);
}

String? _metricFromTitle(String? title) {
  if (title == null) return null;
  final lower = title.toLowerCase();
  if (lower.startsWith('cpu ')) return 'cpu';
  if (lower.startsWith('ram ')) return 'ram';
  if (lower.startsWith('disk ')) return 'disk';
  return null;
}

String? _serverIdFromTitle(String? title) {
  if (title == null) return null;
  final parts = title.split('—');
  if (parts.length < 2) return null;
  final serverId = parts.sublist(1).join('—').trim();
  return serverId.isEmpty ? null : serverId;
}

List<double> _numbersFromText(String? text) {
  if (text == null) return const [];
  final matches = RegExp(r'-?\d+(?:\.\d+)?').allMatches(text);
  return matches
      .map((m) => double.tryParse(m.group(0) ?? ''))
      .whereType<double>()
      .take(2)
      .toList(growable: false);
}

extension on List<double> {
  double? get firstOrNull => isEmpty ? null : this[0];
}
