import 'dart:convert';

class AlertModel {
  final String id;
  final String serverId;
  final String? serverName;
  final String metric;
  final double value;
  final double threshold;
  final DateTime timestamp;
  final bool isRead;

  const AlertModel({
    required this.id,
    required this.serverId,
    this.serverName,
    required this.metric,
    required this.value,
    required this.threshold,
    required this.timestamp,
    this.isRead = false,
  });

  AlertModel copyWith({bool? isRead}) {
    return AlertModel(
      id: id,
      serverId: serverId,
      serverName: serverName,
      metric: metric,
      value: value,
      threshold: threshold,
      timestamp: timestamp,
      isRead: isRead ?? this.isRead,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'serverId': serverId,
        'serverName': serverName,
        'metric': metric,
        'value': value,
        'threshold': threshold,
        'timestamp': timestamp.toIso8601String(),
        'isRead': isRead,
      };

  factory AlertModel.fromJson(Map<String, dynamic> json) => AlertModel(
        id: json['id'] as String,
        serverId: json['serverId'] as String,
        serverName: json['serverName'] as String?,
        metric: json['metric'] as String,
        value: (json['value'] as num).toDouble(),
        threshold: (json['threshold'] as num).toDouble(),
        timestamp: DateTime.parse(json['timestamp'] as String),
        isRead: json['isRead'] as bool? ?? false,
      );

  static List<AlertModel> listFromJson(String raw) {
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => AlertModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static String listToJson(List<AlertModel> alerts) =>
      jsonEncode(alerts.map((a) => a.toJson()).toList());

  /// Human-readable metric label.
  String get metricLabel => switch (metric) {
        'cpu' => 'CPU',
        'ram' => 'RAM',
        'disk' => 'Disk',
        'unknown' => 'Server',
        _ => metric.toUpperCase(),
      };

  bool get hasStructuredDetails {
    return metric != 'unknown' || value != 0 || threshold != 0;
  }

  String get displayServer => (serverName?.trim().isNotEmpty ?? false)
      ? serverName!.trim()
      : serverId;
}
