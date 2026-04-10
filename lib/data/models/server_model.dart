import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import '../database/app_database.dart';
import '../database/tables.dart';

// Re-export the drift-generated Server type with helpers
extension ServerExtension on Server {
  AuthType get authTypeEnum => AuthType.values[authType];

  List<String> get tagList {
    if (tags == null || tags!.isEmpty) return [];
    return tags!.split(',').map((t) => t.trim()).toList();
  }

  Color? get displayColor {
    if (color == null) return null;
    return Color(color!);
  }

  String get displayName => name.isNotEmpty ? name : host;

  String get connectionString => '$username@$host:$port';
  String get relayServerId {
    final value = relayId?.trim();
    if (value != null && value.isNotEmpty) return value;
    return id.toString();
  }
}

// Companion helper for creating new servers
class ServerFormData {
  final String name;
  final String host;
  final int port;
  final String username;
  final AuthType authType;
  final String credentialStorageKey;
  final String? label;
  final String? notes;
  final List<String> tags;
  final Color? color;
  final double? cpuAlertThreshold;
  final double? memoryAlertThreshold;
  final double? diskAlertThreshold;
  final bool alertsEnabled;

  const ServerFormData({
    required this.name,
    required this.host,
    required this.port,
    required this.username,
    required this.authType,
    required this.credentialStorageKey,
    this.label,
    this.notes,
    this.tags = const [],
    this.color,
    this.cpuAlertThreshold,
    this.memoryAlertThreshold,
    this.diskAlertThreshold,
    this.alertsEnabled = true,
  });

  ServersCompanion toCompanion() => ServersCompanion.insert(
    name: name,
    host: host,
    port: Value(port),
    username: username,
    authType: Value(authType.index),
    credentialStorageKey: credentialStorageKey,
    label: Value(label),
    notes: Value(notes),
    tags: Value(tags.isEmpty ? null : tags.join(',')),
    color: Value(color?.value),
    cpuAlertThreshold: Value(cpuAlertThreshold),
    memoryAlertThreshold: Value(memoryAlertThreshold),
    diskAlertThreshold: Value(diskAlertThreshold),
    alertsEnabled: Value(alertsEnabled),
  );
}
