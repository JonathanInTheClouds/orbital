// ── DockerContainerState ──────────────────────────────────────────────────────

enum DockerContainerState {
  running,
  exited,
  paused,
  restarting,
  dead,
  created,
  removing,
  unknown;

  static DockerContainerState fromString(String s) {
    return switch (s.toLowerCase()) {
      'running' => running,
      'exited' => exited,
      'paused' => paused,
      'restarting' => restarting,
      'dead' => dead,
      'created' => created,
      'removing' => removing,
      _ => unknown,
    };
  }

  bool get isRunning => this == running;
  bool get isStopped => this == exited || this == dead;
  bool get isTransitioning => this == restarting || this == removing;
}

// ── DockerContainer ───────────────────────────────────────────────────────────

class DockerContainer {
  final String id;
  final String shortId;
  final String name;
  final String image;
  final DockerContainerState state;
  final String status;
  final List<String> ports;
  final DateTime? createdAt;

  // Stats (populated separately from docker stats)
  final double? cpuPercent;
  final int? memUsageBytes;
  final int? memLimitBytes;
  final int? netRxBytes;
  final int? netTxBytes;
  final int? blockReadBytes;
  final int? blockWriteBytes;
  final int? pids;

  const DockerContainer({
    required this.id,
    required this.shortId,
    required this.name,
    required this.image,
    required this.state,
    required this.status,
    required this.ports,
    this.createdAt,
    this.cpuPercent,
    this.memUsageBytes,
    this.memLimitBytes,
    this.netRxBytes,
    this.netTxBytes,
    this.blockReadBytes,
    this.blockWriteBytes,
    this.pids,
  });

  double? get memPercent {
    if (memUsageBytes == null || memLimitBytes == null || memLimitBytes == 0) {
      return null;
    }
    return (memUsageBytes! / memLimitBytes!) * 100;
  }

  /// Returns a copy with stats merged in.
  DockerContainer withStats(DockerStats stats) {
    return DockerContainer(
      id: id,
      shortId: shortId,
      name: name,
      image: image,
      state: state,
      status: status,
      ports: ports,
      createdAt: createdAt,
      cpuPercent: stats.cpuPercent,
      memUsageBytes: stats.memUsageBytes,
      memLimitBytes: stats.memLimitBytes,
      netRxBytes: stats.netRxBytes,
      netTxBytes: stats.netTxBytes,
      blockReadBytes: stats.blockReadBytes,
      blockWriteBytes: stats.blockWriteBytes,
      pids: stats.pids,
    );
  }

  /// Parse from `docker ps -a --format '{{json .}}'` output line.
  factory DockerContainer.fromDockerJson(Map<String, dynamic> json) {
    final id = json['ID'] as String? ?? json['Id'] as String? ?? '';
    final portsRaw = json['Ports'] as String? ?? '';
    return DockerContainer(
      id: id,
      shortId: id.length >= 12 ? id.substring(0, 12) : id,
      name: (json['Names'] as String? ?? '').replaceAll('/', '').trim(),
      image: json['Image'] as String? ?? '',
      state: DockerContainerState.fromString(
          json['State'] as String? ?? 'unknown'),
      status: json['Status'] as String? ?? '',
      ports: portsRaw.isEmpty
          ? []
          : portsRaw.split(', ').where((p) => p.isNotEmpty).toList(),
    );
  }
}

// ── DockerStats ───────────────────────────────────────────────────────────────

class DockerStats {
  final String containerId;
  final double cpuPercent;
  final int memUsageBytes;
  final int memLimitBytes;
  final int netRxBytes;
  final int netTxBytes;
  final int blockReadBytes;
  final int blockWriteBytes;
  final int pids;

  const DockerStats({
    required this.containerId,
    required this.cpuPercent,
    required this.memUsageBytes,
    required this.memLimitBytes,
    required this.netRxBytes,
    required this.netTxBytes,
    required this.blockReadBytes,
    required this.blockWriteBytes,
    required this.pids,
  });

  /// Parse from `docker stats --no-stream --format '{{json .}}'` output line.
  factory DockerStats.fromDockerJson(Map<String, dynamic> json) {
    return DockerStats(
      containerId: json['ID'] as String? ?? json['Id'] as String? ?? '',
      cpuPercent: _parsePercent(json['CPUPerc'] as String? ?? '0%'),
      memUsageBytes: _parseBytes(json['MemUsage'] as String? ?? '0B / 0B', 0),
      memLimitBytes: _parseBytes(json['MemUsage'] as String? ?? '0B / 0B', 1),
      netRxBytes: _parseBytes(json['NetIO'] as String? ?? '0B / 0B', 0),
      netTxBytes: _parseBytes(json['NetIO'] as String? ?? '0B / 0B', 1),
      blockReadBytes:
          _parseBytes(json['BlockIO'] as String? ?? '0B / 0B', 0),
      blockWriteBytes:
          _parseBytes(json['BlockIO'] as String? ?? '0B / 0B', 1),
      pids: int.tryParse(json['PIDs'] as String? ?? '0') ?? 0,
    );
  }

  static double _parsePercent(String s) {
    return double.tryParse(s.replaceAll('%', '').trim()) ?? 0;
  }

  /// Parse bytes from strings like "1.2GiB / 3.8GiB" or "500MiB / 1GiB".
  static int _parseBytes(String s, int index) {
    final parts = s.split('/');
    if (index >= parts.length) return 0;
    return _bytesFromHuman(parts[index].trim());
  }

  static int _bytesFromHuman(String s) {
    final clean = s.trim();
    final suffixes = {
      'GiB': 1024 * 1024 * 1024,
      'MiB': 1024 * 1024,
      'KiB': 1024,
      'GB': 1000 * 1000 * 1000,
      'MB': 1000 * 1000,
      'KB': 1000,
      'B': 1,
    };
    for (final entry in suffixes.entries) {
      if (clean.endsWith(entry.key)) {
        final num =
            double.tryParse(clean.replaceAll(entry.key, '').trim()) ?? 0;
        return (num * entry.value).round();
      }
    }
    return int.tryParse(clean) ?? 0;
  }
}

// ── DockerImage ───────────────────────────────────────────────────────────────

class DockerImage {
  final String id;
  final String repository;
  final String tag;
  final int sizeBytes;
  final DateTime? createdAt;

  const DockerImage({
    required this.id,
    required this.repository,
    required this.tag,
    required this.sizeBytes,
    this.createdAt,
  });

  String get displayName =>
      tag.isNotEmpty && tag != '<none>' ? '$repository:$tag' : repository;

  /// Parse from `docker images --format '{{json .}}'` output line.
  factory DockerImage.fromDockerJson(Map<String, dynamic> json) {
    return DockerImage(
      id: json['ID'] as String? ?? '',
      repository: json['Repository'] as String? ?? '<none>',
      tag: json['Tag'] as String? ?? '<none>',
      sizeBytes: _parseSize(json['Size'] as String? ?? '0B'),
    );
  }

  static int _parseSize(String s) => DockerStats._bytesFromHuman(s);
}
