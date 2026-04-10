import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/logging/orbital_logger.dart';
import '../../../core/models/alert_thresholds.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/settings/settings_repository.dart';
import '../../../services/biometrics_service.dart';
import '../../../services/notification_service.dart';
import '../../servers/providers/metric_history_provider.dart';
import '../../servers/services/agent_threshold_sync_service.dart';
import '../../terminal/session_log_manager.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Top-level Settings screen — navigation rows only
// ═══════════════════════════════════════════════════════════════════════════════

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          _buildAppBar(context),
          SliverList(
            delegate: SliverChildListDelegate([
              const SizedBox(height: 16),
              _buildCard(context, [
                _NavTile(
                  icon: Icons.timer_rounded,
                  label: 'Monitoring',
                  sub: 'Poll interval, connect timeout',
                  onTap: () => context.push('/settings/monitoring'),
                ),
              ]),
              const SizedBox(height: 12),
              _buildCard(context, [
                _NavTile(
                  icon: Icons.notifications_rounded,
                  label: 'Alert Thresholds',
                  sub: 'CPU, RAM, Disk defaults',
                  onTap: () => context.push('/settings/thresholds'),
                ),
              ]),
              const SizedBox(height: 12),
              _buildCard(context, [
                _NavTile(
                  icon: Icons.cell_tower_rounded,
                  label: 'Relay',
                  sub: 'Push notification relay settings',
                  onTap: () => context.push('/settings/relay'),
                ),
              ]),
              const SizedBox(height: 12),
              _buildCard(context, [
                _NavTile(
                  icon: Icons.palette_rounded,
                  label: 'Appearance',
                  sub: 'Theme and dark style',
                  onTap: () => context.push('/settings/appearance'),
                ),
              ]),
              const SizedBox(height: 12),
              _buildCard(context, [
                _NavTile(
                  icon: Icons.fingerprint_rounded,
                  label: 'Security',
                  sub: 'Biometric app lock',
                  onTap: () => context.push('/settings/security'),
                ),
              ]),
              const SizedBox(height: 12),
              _buildCard(context, [
                _NavTile(
                  icon: Icons.code_rounded,
                  label: 'Developer',
                  sub: 'Debug logs, reset settings',
                  onTap: () => context.push('/settings/developer'),
                ),
              ]),
              const SizedBox(height: 12),
              _buildCard(context, [
                _NavTile(
                  icon: Icons.info_outline_rounded,
                  label: 'About',
                  sub: 'Version, app info',
                  onTap: () => context.push('/settings/about'),
                ),
              ]),
              const SizedBox(height: 48),
            ]),
          ),
        ],
      ),
    );
  }

  SliverAppBar _buildAppBar(BuildContext context) {
    return SliverAppBar(
      floating: true,
      pinned: false,
      snap: true,
      centerTitle: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      surfaceTintColor: Colors.transparent,
      expandedHeight: 100,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.only(bottom: 16),
        title: Text(
          'Settings',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurface,
            letterSpacing: -0.5,
          ),
        ),
        background: Container(color: Theme.of(context).scaffoldBackgroundColor),
      ),
    );
  }

  Widget _buildCard(BuildContext context, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: _surfaceCardDecoration(context),
        child: Column(children: children),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Monitoring screen
// ═══════════════════════════════════════════════════════════════════════════════

class MonitoringSettingsScreen extends ConsumerWidget {
  const MonitoringSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: _subAppBar(context, 'Monitoring'),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 8),
          _sectionHeader(context, 'SSH'),
          _card(context, [
            _SliderTile(
              icon: Icons.timer_rounded,
              label: 'Poll Interval',
              description: 'How often metrics are fetched from each server.',
              value: settings.pollIntervalSeconds.toDouble(),
              min: 5,
              max: 60,
              divisions: 11,
              formatValue: (v) => '${v.round()}s',
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .setPollInterval(v.round()),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            _SliderTile(
              icon: Icons.wifi_rounded,
              label: 'Connect Timeout',
              description:
                  'Maximum time to wait when opening an SSH connection.',
              value: settings.connectTimeoutSeconds.toDouble(),
              min: 5,
              max: 60,
              divisions: 11,
              formatValue: (v) => '${v.round()}s',
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .setConnectTimeout(v.round()),
            ),
          ]),
          const SizedBox(height: 48),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Alert Thresholds screen
// ═══════════════════════════════════════════════════════════════════════════════

class ThresholdsSettingsScreen extends ConsumerStatefulWidget {
  const ThresholdsSettingsScreen({super.key});

  @override
  ConsumerState<ThresholdsSettingsScreen> createState() =>
      _ThresholdsSettingsScreenState();
}

class _ThresholdsSettingsScreenState
    extends ConsumerState<ThresholdsSettingsScreen> {
  late AlertThresholdPreset _preset;
  Timer? _syncDebounce;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _preset = detectPreset(
      AlertThresholdProfile(
        cpu: settings.cpuAlertThreshold,
        memory: settings.memoryAlertThreshold,
        disk: settings.diskAlertThreshold,
      ),
    );
  }

  Future<void> _applyPreset(AlertThresholdPreset preset) async {
    setState(() => _preset = preset);
    if (preset == AlertThresholdPreset.custom) return;
    final notifier = ref.read(settingsProvider.notifier);
    final profile = switch (preset) {
      AlertThresholdPreset.relaxed => AlertThresholdProfile.relaxed,
      AlertThresholdPreset.balanced => AlertThresholdProfile.balanced,
      AlertThresholdPreset.strict => AlertThresholdProfile.strict,
      AlertThresholdPreset.custom => null,
    };
    if (profile == null) return;
    await notifier.setCpuAlertThreshold(profile.cpu);
    await notifier.setMemoryAlertThreshold(profile.memory);
    await notifier.setDiskAlertThreshold(profile.disk);
    _scheduleAgentSync();
  }

  void _scheduleAgentSync() {
    _syncDebounce?.cancel();
    _syncDebounce = Timer(const Duration(seconds: 1), () async {
      final settings = ref.read(settingsProvider);
      await ref.read(agentThresholdSyncServiceProvider).syncServersUsingDefaults(
            AlertThresholdProfile(
              cpu: settings.cpuAlertThreshold,
              memory: settings.memoryAlertThreshold,
              disk: settings.diskAlertThreshold,
            ),
          );
    });
  }

  @override
  void dispose() {
    _syncDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: _subAppBar(context, 'Alert Thresholds'),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 8),
          _sectionHeader(context, 'Default Thresholds'),
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: Text(
              'These apply to servers that don\'t have their own thresholds configured.',
              style: TextStyle(
                fontSize: 13,
                color: OrbitalColors.textMuted,
                height: 1.5,
              ),
            ),
          ),
          _ThresholdPresetSelector(
            selected: _preset,
            onSelected: _applyPreset,
          ),
          if (_preset == AlertThresholdPreset.custom) ...[
            const SizedBox(height: 12),
            _card(context, [
            _SliderTile(
              icon: Icons.memory_rounded,
              label: 'CPU',
              value: settings.cpuAlertThreshold,
              min: 50,
              max: 100,
              divisions: 10,
              formatValue: (v) => '${v.round()}%',
              accentColor: OrbitalColors.cpu,
              onChanged: (v) =>
                  ref.read(settingsProvider.notifier).setCpuAlertThreshold(v).then(
                        (_) => _scheduleAgentSync(),
                      ),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            _SliderTile(
              icon: Icons.storage_rounded,
              label: 'RAM',
              value: settings.memoryAlertThreshold,
              min: 50,
              max: 100,
              divisions: 10,
              formatValue: (v) => '${v.round()}%',
              accentColor: OrbitalColors.memory,
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .setMemoryAlertThreshold(v)
                  .then((_) => _scheduleAgentSync()),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            _SliderTile(
              icon: Icons.disc_full_rounded,
              label: 'Disk',
              value: settings.diskAlertThreshold,
              min: 50,
              max: 100,
              divisions: 10,
              formatValue: (v) => '${v.round()}%',
              accentColor: OrbitalColors.disk,
              onChanged: (v) =>
                  ref.read(settingsProvider.notifier).setDiskAlertThreshold(v).then(
                        (_) => _scheduleAgentSync(),
                      ),
            ),
          ]),
          ],
          const SizedBox(height: 48),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Relay Settings screen
// ═══════════════════════════════════════════════════════════════════════════════

class RelaySettingsScreen extends ConsumerStatefulWidget {
  const RelaySettingsScreen({super.key});

  @override
  ConsumerState<RelaySettingsScreen> createState() =>
      _RelaySettingsScreenState();
}

class _RelaySettingsScreenState extends ConsumerState<RelaySettingsScreen> {
  late final TextEditingController _urlController;
  late final TextEditingController _tokenController;
  bool _isSaving = false;
  bool _isRegistering = false;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _urlController = TextEditingController(text: settings.relayUrl);
    _tokenController = TextEditingController(text: settings.relayAuthToken);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      final notifier = ref.read(settingsProvider.notifier);
      await notifier.setRelayUrl(_urlController.text.trim());
      await notifier.setRelayAuthToken(_tokenController.text.trim());

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Relay settings saved')));
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _saveAndRegister() async {
    if (_isRegistering) return;
    setState(() => _isRegistering = true);
    await _save();
    final result = await NotificationService.instance.registerWithRelay(ref);

    if (!mounted) return;
    setState(() => _isRegistering = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: _subAppBar(context, 'Relay'),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 8),
          _sectionHeader(context, 'Connection'),
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: Text(
              'The relay server receives threshold breach alerts from your agents '
              'and forwards them to this device as push notifications. '
              'Server IDs are managed automatically.',
              style: TextStyle(
                fontSize: 13,
                color: OrbitalColors.textMuted,
                height: 1.5,
              ),
            ),
          ),
          _card(context, [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _RelayTextField(
                    controller: _urlController,
                    label: 'Relay URL',
                    hint: 'http://your-server:8080',
                    icon: Icons.cloud_outlined,
                    keyboardType: TextInputType.url,
                  ),
                  const SizedBox(height: 12),
                  _RelayTextField(
                    controller: _tokenController,
                    label: 'Auth Token',
                    hint: 'Matches relay config.json auth_token',
                    icon: Icons.key_rounded,
                    obscureText: true,
                  ),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _isSaving || _isRegistering ? null : _save,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(
                          color: Theme.of(context).colorScheme.primary,
                          width: 1.2,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Save',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSaving || _isRegistering
                          ? null
                          : _saveAndRegister,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        _isRegistering ? 'Registering…' : 'Save & Register',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 48),
        ],
      ),
    );
  }
}

// ── _RelayTextField ───────────────────────────────────────────────────────────

class _RelayTextField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final bool obscureText;

  const _RelayTextField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.obscureText = false,
  });

  @override
  State<_RelayTextField> createState() => _RelayTextFieldState();
}

class _RelayTextFieldState extends State<_RelayTextField> {
  late bool _obscure;

  @override
  void initState() {
    super.initState();
    _obscure = widget.obscureText;
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      keyboardType: widget.keyboardType,
      obscureText: _obscure,
      style: TextStyle(
        fontSize: 15,
        color: Theme.of(context).colorScheme.onSurface,
      ),
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        prefixIcon: Icon(
          widget.icon,
          size: 18,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        suffixIcon: widget.obscureText
            ? IconButton(
                icon: Icon(
                  _obscure
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              )
            : null,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Appearance screen
// ═══════════════════════════════════════════════════════════════════════════════

// ── TintColorPicker widget ────────────────────────────────────────────────────

class _TintColorPicker extends StatelessWidget {
  const _TintColorPicker({
    required this.selected,
    required this.onSelect,
  });

  final AppTintColor selected;
  final ValueChanged<AppTintColor> onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: tintColorPresets.entries.map((entry) {
          final isSelected = entry.key == selected;
          return GestureDetector(
            onTap: () => onSelect(entry.key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: entry.value,
                shape: BoxShape.circle,
                border: isSelected
                    ? Border.all(
                        color: Theme.of(context).colorScheme.onSurface,
                        width: 2.5,
                      )
                    : Border.all(color: Colors.transparent, width: 2.5),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: entry.value.withOpacity(0.5),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: isSelected
                  ? const Icon(Icons.check_rounded,
                      color: Colors.white, size: 18)
                  : null,
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── AppearanceSettingsScreen ──────────────────────────────────────────────────

class AppearanceSettingsScreen extends ConsumerWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(settingsProvider.select((s) => s.themeMode));
    final darkStyle = ref.watch(settingsProvider.select((s) => s.darkStyle));
    final tint = ref.watch(settingsProvider.select((s) => s.tintColor));
    final isDarkActive = mode == AppThemeMode.dark || mode == AppThemeMode.system;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: _subAppBar(context, 'Appearance'),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 8),
          _sectionHeader(context, 'Theme'),
          _card(context, [
            RadioListTile<AppThemeMode>(
              value: AppThemeMode.dark,
              groupValue: mode,
              onChanged: (value) {
                if (value != null) {
                  ref.read(settingsProvider.notifier).setThemeMode(value);
                }
              },
              activeColor: Theme.of(context).colorScheme.primary,
              title: const Text('Dark'),
              subtitle: const Text('Default Orbital appearance'),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            RadioListTile<AppThemeMode>(
              value: AppThemeMode.light,
              groupValue: mode,
              onChanged: (value) {
                if (value != null) {
                  ref.read(settingsProvider.notifier).setThemeMode(value);
                }
              },
              activeColor: Theme.of(context).colorScheme.primary,
              title: const Text('Light'),
              subtitle: const Text('Brighter UI for daytime use'),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            RadioListTile<AppThemeMode>(
              value: AppThemeMode.system,
              groupValue: mode,
              onChanged: (value) {
                if (value != null) {
                  ref.read(settingsProvider.notifier).setThemeMode(value);
                }
              },
              activeColor: Theme.of(context).colorScheme.primary,
              title: const Text('Use system setting'),
              subtitle: const Text('Follow device dark mode preference'),
            ),
          ]),
          const SizedBox(height: 24),
          _sectionHeader(context, 'Dark Style'),
          AnimatedOpacity(
            opacity: isDarkActive ? 1.0 : 0.4,
            duration: const Duration(milliseconds: 200),
            child: IgnorePointer(
              ignoring: !isDarkActive,
              child: _card(context, [
                RadioListTile<DarkStyle>(
                  value: DarkStyle.standard,
                  groupValue: darkStyle,
                  onChanged: (value) {
                    if (value != null) {
                      ref.read(settingsProvider.notifier).setDarkStyle(value);
                    }
                  },
                  activeColor: Theme.of(context).colorScheme.primary,
                  title: const Text('Standard'),
                  subtitle: const Text('Deep navy dark theme'),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                RadioListTile<DarkStyle>(
                  value: DarkStyle.black,
                  groupValue: darkStyle,
                  onChanged: (value) {
                    if (value != null) {
                      ref.read(settingsProvider.notifier).setDarkStyle(value);
                    }
                  },
                  activeColor: Theme.of(context).colorScheme.primary,
                  title: const Text('Black'),
                  subtitle: const Text('True black for AMOLED displays'),
                ),
              ]),
            ),
          ),
          if (!isDarkActive)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 4),
              child: Text(
                'Dark Style only applies when a dark theme is active.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 24),
          _sectionHeader(context, 'Tint Color'),
          _card(context, [
            _TintColorPicker(
              selected: tint,
              onSelect: (color) =>
                  ref.read(settingsProvider.notifier).setTintColor(color),
            ),
          ]),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Security screen
// ═══════════════════════════════════════════════════════════════════════════════

class SecuritySettingsScreen extends ConsumerStatefulWidget {
  const SecuritySettingsScreen({super.key});

  @override
  ConsumerState<SecuritySettingsScreen> createState() =>
      _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends ConsumerState<SecuritySettingsScreen> {
  final BiometricsService _biometricsService = BiometricsService();
  bool _isUpdating = false;

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(
      settingsProvider.select((s) => s.biometricLockEnabled),
    );

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: _subAppBar(context, 'Security'),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 8),
          _sectionHeader(context, 'App Lock'),
          _card(context, [
            _SwitchTile(
              icon: Icons.fingerprint_rounded,
              label: 'Biometric Lock',
              sub: 'Require Face ID / fingerprint when opening Orbital',
              value: enabled,
              onChanged: _isUpdating
                  ? null
                  : (value) => _toggleBiometricLock(context, value),
            ),
          ]),
          const SizedBox(height: 12),
          Text(
            'If biometrics are enabled, Orbital will ask for authentication when opened and when returning to the app.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleBiometricLock(BuildContext context, bool enable) async {
    setState(() => _isUpdating = true);

    OrbitalLogger.instance.info(
      'Biometrics',
      enable ? 'User requested biometric lock enable' : 'User requested biometric lock disable',
    );

    try {
      if (!enable) {
        await ref.read(settingsProvider.notifier).setBiometricLockEnabled(false);
        OrbitalLogger.instance.info('Biometrics', 'Biometric lock disabled');
        return;
      }

      final available = await _biometricsService.isBiometricAuthAvailable();
      if (!available) {
        OrbitalLogger.instance.warning('Biometrics', 'Enable failed: biometrics unavailable');
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No enrolled biometrics were found on this device.'),
          ),
        );
        return;
      }

      final authenticated = await _biometricsService.authenticateForUnlock();
      if (!authenticated) {
        OrbitalLogger.instance.warning('Biometrics', 'Enable failed: authentication did not succeed');
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Authentication failed. Biometric lock was not enabled.'),
          ),
        );
        return;
      }

      await ref.read(settingsProvider.notifier).setBiometricLockEnabled(true);
      OrbitalLogger.instance.info('Biometrics', 'Biometric lock enabled');
    } finally {
      if (mounted) {
        setState(() => _isUpdating = false);
      }
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Developer screen
// ═══════════════════════════════════════════════════════════════════════════════

class DeveloperSettingsScreen extends ConsumerWidget {
  const DeveloperSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showPreview = ref.watch(
      settingsProvider.select((s) => s.showPreviewTools),
    );

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: _subAppBar(context, 'Developer'),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 8),
          _sectionHeader(context, 'Logs'),
          _card(context, [
            _NavTile(
              icon: Icons.bug_report_rounded,
              label: 'Debug Logs',
              sub: 'View live app logs',
              onTap: () => context.push('/settings/logs'),
            ),
            const Divider(height: 1, indent: 60, endIndent: 16),
            _NavTile(
              icon: Icons.terminal_rounded,
              label: 'Session Logs',
              sub: 'View and manage terminal recordings',
              onTap: () => context.push('/settings/session-logs'),
            ),
          ]),
          const SizedBox(height: 20),
          _sectionHeader(context, 'UI'),
          _card(context, [
            _SwitchTile(
              icon: Icons.science_rounded,
              label: 'Preview Tools',
              sub: 'Show the beaker icon on the server list',
              value: showPreview,
              onChanged: (v) =>
                  ref.read(settingsProvider.notifier).setShowPreviewTools(v),
            ),
          ]),
          const SizedBox(height: 20),
          _sectionHeader(context, 'Data'),
          _card(context, [
            _ActionTile(
              icon: Icons.history_rounded,
              label: 'Clear Metric History',
              color: OrbitalColors.warning,
              onTap: () => _confirmClearHistory(context, ref),
            ),
          ]),
          const SizedBox(height: 20),
          _sectionHeader(context, 'Danger Zone'),
          _card(context, [
            _ActionTile(
              icon: Icons.restore_rounded,
              label: 'Reset All Settings',
              color: OrbitalColors.danger,
              onTap: () => _confirmReset(context, ref),
            ),
          ]),
          const SizedBox(height: 48),
        ],
      ),
    );
  }

  Future<void> _confirmClearHistory(BuildContext context, WidgetRef ref) async {
    final totalSamples = ref
        .read(metricHistoryNotifierProvider.notifier)
        .totalSamples;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: Theme.of(context).dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Icon(
              Icons.history_rounded,
              size: 40,
              color: OrbitalColors.warning,
            ),
            const SizedBox(height: 16),
            const Text(
              'Clear Metric History?',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: OrbitalColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$totalSamples samples across all servers will be removed.\nHistory charts will start fresh.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: OrbitalColors.textMuted,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      foregroundColor: OrbitalColors.textSecondary,
                      side: BorderSide(color: Theme.of(context).dividerColor),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: OrbitalColors.warning,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Clear',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      ref.read(metricHistoryNotifierProvider.notifier).clearAll();
      OrbitalLogger.instance.info('Settings', 'Metric history cleared');
    }
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: Theme.of(context).dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Icon(
              Icons.restore_rounded,
              size: 40,
              color: OrbitalColors.danger,
            ),
            const SizedBox(height: 16),
            const Text(
              'Reset All Settings?',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: OrbitalColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'All settings will be restored to their defaults.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: OrbitalColors.textMuted,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      foregroundColor: OrbitalColors.textSecondary,
                      side: BorderSide(color: Theme.of(context).dividerColor),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: OrbitalColors.danger,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Reset',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      await ref.read(settingsProvider.notifier).resetAll();
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Session Logs screen
// ═══════════════════════════════════════════════════════════════════════════════

class SessionLogsScreen extends StatefulWidget {
  const SessionLogsScreen({super.key});

  @override
  State<SessionLogsScreen> createState() => _SessionLogsScreenState();
}

class _SessionLogsScreenState extends State<SessionLogsScreen> {
  List<File> _files = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final files = await SessionLogManager.listSessions();
    if (mounted)
      setState(() {
        _files = files;
        _loading = false;
      });
  }

  Future<void> _delete(File file) async {
    await file.delete();
    await _load();
  }

  Future<void> _view(File file) async {
    final content = await file.readAsString();
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (_, controller) => Column(
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                file.path.split('/').last,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: OrbitalColors.textSecondary,
                  fontFamily: 'Menlo',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                controller: controller,
                padding: const EdgeInsets.all(16),
                child: Text(
                  content,
                  style: const TextStyle(
                    fontSize: 11,
                    color: OrbitalColors.textSecondary,
                    fontFamily: 'Menlo',
                    height: 1.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 20,
            color: OrbitalColors.textSecondary,
          ),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Session Logs',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: OrbitalColors.textPrimary,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.refresh_rounded,
              color: OrbitalColors.textSecondary,
            ),
            onPressed: _load,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primary,
                strokeWidth: 2,
              ),
            )
          : _files.isEmpty
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.terminal_rounded,
                    size: 48,
                    color: OrbitalColors.textMuted,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'No session logs',
                    style: TextStyle(
                      fontSize: 16,
                      color: OrbitalColors.textSecondary,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Logs are saved when you use the terminal',
                    style: TextStyle(
                      fontSize: 13,
                      color: OrbitalColors.textMuted,
                    ),
                  ),
                ],
              ),
            )
          : ListView.separated(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: _files.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final file = _files[i];
                final name = file.path.split('/').last;
                final stat = file.statSync();
                final size = _formatSize(stat.size);
                return Dismissible(
                  key: ValueKey(file.path),
                  direction: DismissDirection.endToStart,
                  dismissThresholds: const {DismissDirection.endToStart: 0.15},
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 24),
                    decoration: BoxDecoration(
                      color: OrbitalColors.danger.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: OrbitalColors.danger.withOpacity(0.3),
                      ),
                    ),
                    child: const Icon(
                      Icons.delete_rounded,
                      color: OrbitalColors.danger,
                    ),
                  ),
                  onDismissed: (_) => _delete(file),
                  child: GestureDetector(
                    onTap: () => _view(file),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.white.withOpacity(0.08)
                              : Colors.black.withOpacity(0.08),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Icon(
                              Icons.terminal_rounded,
                              size: 18,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: OrbitalColors.textPrimary,
                                    fontFamily: 'Menlo',
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  size,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: OrbitalColors.textMuted,
                                    fontFamily: 'Menlo',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: OrbitalColors.textMuted,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '$bytes B';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// About screen
// ═══════════════════════════════════════════════════════════════════════════════

class AboutSettingsScreen extends StatelessWidget {
  const AboutSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: _subAppBar(context, 'About'),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 8),
          _card(context, [
            _InfoTile(label: 'App', value: 'Orbital'),
            const Divider(height: 1, indent: 16, endIndent: 16),
            _InfoTile(label: 'Version', value: '1.0.0'),
            const Divider(height: 1, indent: 16, endIndent: 16),
            _InfoTile(label: 'Build', value: 'Debug'),
          ]),
          const SizedBox(height: 48),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// LogsScreen
// ═══════════════════════════════════════════════════════════════════════════════

class LogsScreen extends ConsumerStatefulWidget {
  const LogsScreen({super.key});

  @override
  ConsumerState<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends ConsumerState<LogsScreen> {
  LogLevel _minLevel = LogLevel.debug;
  final _scrollController = ScrollController();
  final List<LogEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    _entries.addAll(OrbitalLogger.instance.entriesAtLevel(_minLevel));
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _copyAll() async {
    final text = _entries.map((e) => e.formatted).join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
    }
  }

  Future<void> _clear() async {
    await OrbitalLogger.instance.clear();
    setState(() => _entries.clear());
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<LogEntry>>(logStreamProvider, (_, next) {
      final entry = next.asData?.value;
      if (entry != null && entry.level >= _minLevel) {
        setState(() => _entries.add(entry));
        _scrollToBottom();
      }
    });

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 20,
            color: OrbitalColors.textSecondary,
          ),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Debug Logs',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: OrbitalColors.textPrimary,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.copy_rounded,
              color: OrbitalColors.textSecondary,
              size: 20,
            ),
            onPressed: _copyAll,
          ),
          IconButton(
            icon: const Icon(
              Icons.delete_outline_rounded,
              color: OrbitalColors.textSecondary,
              size: 20,
            ),
            onPressed: _clear,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          _buildLevelFilter(),
          Expanded(child: _buildLogList()),
        ],
      ),
    );
  }

  Widget _buildLevelFilter() {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: LogLevel.values.map((level) {
          final selected = level == _minLevel;
          final color = _levelColor(level);
          return GestureDetector(
            onTap: () => setState(() {
              _minLevel = level;
              _entries
                ..clear()
                ..addAll(OrbitalLogger.instance.entriesAtLevel(level));
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: selected
                    ? color.withOpacity(0.15)
                    : Theme.of(context).inputDecorationTheme.fillColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected
                      ? color.withOpacity(0.4)
                      : Theme.of(context).brightness == Brightness.dark
                          ? Colors.white.withOpacity(0.12)
                          : Colors.black.withOpacity(0.12),
                ),
              ),
              child: Text(
                level.label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: selected ? color : OrbitalColors.textMuted,
                  fontFamily: 'Menlo',
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildLogList() {
    if (_entries.isEmpty) {
      return const Center(
        child: Text(
          'No log entries',
          style: TextStyle(fontSize: 14, color: OrbitalColors.textMuted),
        ),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(12),
      itemCount: _entries.length,
      itemBuilder: (_, i) => _LogEntryRow(entry: _entries[i]),
    );
  }

  Color _levelColor(LogLevel level) => switch (level) {
    LogLevel.debug => OrbitalColors.textMuted,
    LogLevel.info => Theme.of(context).colorScheme.primary,
    LogLevel.warning => OrbitalColors.warning,
    LogLevel.error => OrbitalColors.danger,
  };
}

class _LogEntryRow extends StatelessWidget {
  final LogEntry entry;
  const _LogEntryRow({required this.entry});

  Color _color(BuildContext context) => switch (entry.level) {
    LogLevel.debug => OrbitalColors.textMuted,
    LogLevel.info => Theme.of(context).colorScheme.primary,
    LogLevel.warning => OrbitalColors.warning,
    LogLevel.error => OrbitalColors.danger,
  };

  @override
  Widget build(BuildContext context) {
    final color = _color(context);
    final ts = entry.timestamp
        .toIso8601String()
        .replaceFirst('T', ' ')
        .substring(11, 23);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            padding: const EdgeInsets.symmetric(vertical: 2),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            alignment: Alignment.center,
            child: Text(
              entry.level.label.substring(0, 1),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: color,
                fontFamily: 'Menlo',
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      ts,
                      style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context).textTheme.bodySmall?.color ?? OrbitalColors.textMuted,
                        fontFamily: 'Menlo',
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      entry.tag,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontFamily: 'Menlo',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  entry.message,
                  style: TextStyle(
                    fontSize: 12,
                    color: color,
                    fontFamily: 'Menlo',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Shared helpers
// ═══════════════════════════════════════════════════════════════════════════════

AppBar _subAppBar(BuildContext context, String title) {
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
    title: Text(
      title,
      style: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    ),
  );
}

Widget _sectionHeader(BuildContext context, String title) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
    child: Text(
      title.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color:
            Theme.of(context).textTheme.bodySmall?.color ??
            OrbitalColors.textMuted,
        letterSpacing: 1.2,
      ),
    ),
  );
}

Widget _card(BuildContext context, List<Widget> children) {
  return Container(
    decoration: _surfaceCardDecoration(context),
    child: Column(children: children),
  );
}

BoxDecoration _surfaceCardDecoration(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return BoxDecoration(
    color: Theme.of(context).colorScheme.surface,
    borderRadius: BorderRadius.circular(16),
    border: isDark
        ? Border.all(color: Colors.white.withOpacity(0.08))
        : null,
    boxShadow: isDark
        ? null
        : [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
  );
}

// ── _NavTile ──────────────────────────────────────────────────────────────────

class _NavTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? sub;
  final VoidCallback onTap;

  const _NavTile({
    required this.icon,
    required this.label,
    this.sub,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 17, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  if (sub != null)
                    Text(
                      sub!,
                      style: TextStyle(
                        fontSize: 12,
                        color:
                            Theme.of(context).textTheme.bodySmall?.color ??
                            OrbitalColors.textMuted,
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color:
                  Theme.of(context).textTheme.bodySmall?.color ??
                  OrbitalColors.textMuted,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

// ── _ActionTile ───────────────────────────────────────────────────────────────

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 17, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: color.withOpacity(0.5),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

// ── _InfoTile ─────────────────────────────────────────────────────────────────

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;

  const _InfoTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              color:
                  Theme.of(context).textTheme.bodySmall?.color ??
                  OrbitalColors.textMuted,
              fontFamily: 'Menlo',
            ),
          ),
        ],
      ),
    );
  }
}

// ── _SwitchTile ───────────────────────────────────────────────────────────────

class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? sub;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _SwitchTile({
    required this.icon,
    required this.label,
    required this.value,
    this.onChanged,
    this.sub,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 17, color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                if (sub != null)
                  Text(
                    sub!,
                    style: TextStyle(
                      fontSize: 12,
                      color:
                          Theme.of(context).textTheme.bodySmall?.color ??
                          OrbitalColors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: Theme.of(context).colorScheme.primary,
            activeTrackColor: Theme.of(
              context,
            ).colorScheme.primary.withOpacity(0.3),
          ),
        ],
      ),
    );
  }
}

class _ThresholdPresetSelector extends StatelessWidget {
  final AlertThresholdPreset selected;
  final ValueChanged<AlertThresholdPreset> onSelected;

  const _ThresholdPresetSelector({
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return _card(context, [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _presetChip(
              context,
              label: 'Relaxed',
              preset: AlertThresholdPreset.relaxed,
              description: '95/95/92',
            ),
            _presetChip(
              context,
              label: 'Balanced',
              preset: AlertThresholdPreset.balanced,
              description: '90/90/85',
            ),
            _presetChip(
              context,
              label: 'Strict',
              preset: AlertThresholdPreset.strict,
              description: '75/80/75',
            ),
            _presetChip(
              context,
              label: 'Custom',
              preset: AlertThresholdPreset.custom,
              description: 'Manual sliders',
            ),
          ],
        ),
      ),
    ]);
  }

  Widget _presetChip(
    BuildContext context, {
    required String label,
    required AlertThresholdPreset preset,
    required String description,
  }) {
    final active = selected == preset;
    return ChoiceChip(
      selected: active,
      onSelected: (_) => onSelected(preset),
      label: Text('$label • $description'),
      selectedColor: Theme.of(context).colorScheme.primary.withOpacity(0.16),
      labelStyle: TextStyle(
        color: active
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.onSurfaceVariant,
        fontWeight: active ? FontWeight.w600 : FontWeight.w500,
      ),
      side: BorderSide(
        color: active
            ? Theme.of(context).colorScheme.primary.withOpacity(0.45)
            : Theme.of(context).brightness == Brightness.dark
                ? Colors.white.withOpacity(0.12)
                : Colors.black.withOpacity(0.12),
      ),
    );
  }
}

// ── _SliderTile ───────────────────────────────────────────────────────────────

class _SliderTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? description;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String Function(double) formatValue;
  final ValueChanged<double> onChanged;
  final Color? accentColor;

  const _SliderTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.formatValue,
    required this.onChanged,
    this.description,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = accentColor ?? Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    if (description != null)
                      Text(
                        description!,
                        style: TextStyle(
                          fontSize: 12,
                          color:
                              Theme.of(context).textTheme.bodySmall?.color ??
                              OrbitalColors.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
              Text(
                formatValue(value),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: color,
                  fontFamily: 'Menlo',
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: color,
              inactiveTrackColor: Theme.of(
                context,
              ).inputDecorationTheme.fillColor,
              thumbColor: color,
              overlayColor: color.withOpacity(0.12),
              trackHeight: 3,
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
