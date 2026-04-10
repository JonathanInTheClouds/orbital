import '../constants/app_constants.dart';
import '../../data/database/app_database.dart';

class AlertThresholdProfile {
  final double cpu;
  final double memory;
  final double disk;

  const AlertThresholdProfile({
    required this.cpu,
    required this.memory,
    required this.disk,
  });

  static const relaxed = AlertThresholdProfile(cpu: 95, memory: 95, disk: 92);
  static const balanced = AlertThresholdProfile(cpu: 90, memory: 90, disk: 85);
  static const strict = AlertThresholdProfile(cpu: 75, memory: 80, disk: 75);

  static const defaults = AlertThresholdProfile(
    cpu: AppConstants.defaultCpuAlertThreshold,
    memory: AppConstants.defaultMemoryAlertThreshold,
    disk: AppConstants.defaultDiskAlertThreshold,
  );

  bool sameAs(AlertThresholdProfile other) =>
      cpu == other.cpu && memory == other.memory && disk == other.disk;

  static AlertThresholdProfile effectiveForServer(
    Server server,
    AlertThresholdProfile appDefaults,
  ) {
    return AlertThresholdProfile(
      cpu: server.cpuAlertThreshold ?? appDefaults.cpu,
      memory: server.memoryAlertThreshold ?? appDefaults.memory,
      disk: server.diskAlertThreshold ?? appDefaults.disk,
    );
  }
}

enum AlertThresholdPreset { relaxed, balanced, strict, custom }

AlertThresholdPreset detectPreset(AlertThresholdProfile profile) {
  if (profile.sameAs(AlertThresholdProfile.relaxed)) {
    return AlertThresholdPreset.relaxed;
  }
  if (profile.sameAs(AlertThresholdProfile.balanced)) {
    return AlertThresholdPreset.balanced;
  }
  if (profile.sameAs(AlertThresholdProfile.strict)) {
    return AlertThresholdPreset.strict;
  }
  return AlertThresholdPreset.custom;
}
