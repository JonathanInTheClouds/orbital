import 'package:flutter/material.dart';

class ServerIconOption {
  final String key;
  final String label;
  final IconData icon;

  const ServerIconOption({
    required this.key,
    required this.label,
    required this.icon,
  });
}

class ServerIconCatalog {
  static const defaultKey = 'server';

  static const options = <ServerIconOption>[
    ServerIconOption(
      key: 'server',
      label: 'Server',
      icon: Icons.dns_rounded,
    ),
    ServerIconOption(
      key: 'terminal',
      label: 'Terminal',
      icon: Icons.terminal_rounded,
    ),
    ServerIconOption(
      key: 'database',
      label: 'Database',
      icon: Icons.storage_rounded,
    ),
    ServerIconOption(
      key: 'cloud',
      label: 'Cloud',
      icon: Icons.cloud_rounded,
    ),
    ServerIconOption(
      key: 'shield',
      label: 'Secure',
      icon: Icons.shield_rounded,
    ),
    ServerIconOption(
      key: 'monitor',
      label: 'Monitor',
      icon: Icons.monitor_rounded,
    ),
  ];

  static IconData resolveIcon(String? key) {
    for (final option in options) {
      if (option.key == key) return option.icon;
    }
    return options.first.icon;
  }
}
