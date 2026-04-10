import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/logging/orbital_logger.dart';
import 'core/theme/app_theme.dart';
import 'data/settings/settings_repository.dart';
import 'firebase_options.dart';
import 'router/app_router.dart';
import 'services/biometrics_service.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await OrbitalLogger.instance.init();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final prefs = await SharedPreferences.getInstance();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
    ),
  );

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const OrbitalApp(),
    ),
  );
}

class OrbitalApp extends ConsumerWidget {
  const OrbitalApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final settings = ref.watch(settingsProvider);
    final tint = AppTheme.resolveColor(settings.tintColor);

    return _NotificationInitializer(
      child: MaterialApp.router(
        title: 'Orbital',
        debugShowCheckedModeBanner: false,
        themeMode: switch (settings.themeMode) {
          AppThemeMode.light => ThemeMode.light,
          AppThemeMode.dark => ThemeMode.dark,
          AppThemeMode.system => ThemeMode.system,
        },
        theme: AppTheme.light(tint),
        darkTheme: settings.darkStyle == DarkStyle.black
            ? AppTheme.black(tint)
            : AppTheme.dark(tint),
        routerConfig: router,
        builder: (context, child) {
          return _BiometricLockGate(
            child: child ?? const SizedBox.shrink(),
          );
        },
      ),
    );
  }
}

class _NotificationInitializer extends ConsumerStatefulWidget {
  final Widget child;
  const _NotificationInitializer({required this.child});

  @override
  ConsumerState<_NotificationInitializer> createState() =>
      _NotificationInitializerState();
}

class _NotificationInitializerState
    extends ConsumerState<_NotificationInitializer> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (Firebase.apps.isEmpty) {
        OrbitalLogger.instance.warning(
          'Notifications',
          'Skipping notification init: Firebase is not initialized',
        );
        return;
      }
      unawaited(NotificationService.instance.init(ref));
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _BiometricLockGate extends ConsumerStatefulWidget {
  final Widget child;
  const _BiometricLockGate({required this.child});

  @override
  ConsumerState<_BiometricLockGate> createState() => _BiometricLockGateState();
}

class _BiometricLockGateState extends ConsumerState<_BiometricLockGate>
    with WidgetsBindingObserver {
  final BiometricsService _biometricsService = BiometricsService();
  ProviderSubscription<bool>? _biometricSettingSubscription;
  bool _locked = false;
  bool _authInProgress = false;
  bool _initialized = false;
  DateTime? _lastBackgroundedAt;
  DateTime? _lastSuccessfulUnlockAt;

  static const _minBackgroundForRelock = Duration.zero;
  static const _postUnlockGracePeriod = Duration(seconds: 8);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _biometricSettingSubscription = ref.listenManual<bool>(
      settingsProvider.select((s) => s.biometricLockEnabled),
      (previous, enabled) {
        OrbitalLogger.instance.info(
          'Biometrics',
          enabled ? 'Biometric lock setting enabled' : 'Biometric lock setting disabled',
        );

        if (enabled && previous == false) {
          _lastSuccessfulUnlockAt = DateTime.now();
          OrbitalLogger.instance.debug(
            'Biometrics',
            'Skipping immediate re-auth after enabling (already verified in settings)',
          );
          return;
        }

        if (enabled) {
          _lockAndAuthenticate();
        } else if (mounted) {
          setState(() => _locked = false);
        }
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeLockState();
    });
  }

  @override
  void dispose() {
    _biometricSettingSubscription?.close();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _lastBackgroundedAt = DateTime.now();
      return;
    }

    if (state == AppLifecycleState.resumed) {
      OrbitalLogger.instance.debug('Biometrics', 'App resumed');
      final enabled = ref.read(settingsProvider).biometricLockEnabled;
      if (!enabled || !_initialized || _authInProgress) return;

      final now = DateTime.now();
      if (_lastSuccessfulUnlockAt != null &&
          now.difference(_lastSuccessfulUnlockAt!) < _postUnlockGracePeriod) {
        OrbitalLogger.instance.debug(
          'Biometrics',
          'Skipping re-lock: within post-unlock grace period',
        );
        return;
      }

      if (_lastBackgroundedAt == null ||
          now.difference(_lastBackgroundedAt!) <= _minBackgroundForRelock) {
        OrbitalLogger.instance.debug(
          'Biometrics',
          'Skipping re-lock: app was not backgrounded long enough',
        );
        return;
      }

      _lockAndAuthenticate();
    }
  }

  Future<void> _initializeLockState() async {
    _initialized = true;
    if (!ref.read(settingsProvider).biometricLockEnabled) {
      if (mounted) {
        setState(() => _locked = false);
      }
      return;
    }

    await _lockAndAuthenticate();
  }

  Future<void> _lockAndAuthenticate() async {
    if (_authInProgress || !mounted) return;

    OrbitalLogger.instance.info('Biometrics', 'App lock engaged; requesting authentication');

    setState(() {
      _locked = true;
      _authInProgress = true;
    });

    final available = await _biometricsService.isBiometricAuthAvailable();
    if (!available) {
      OrbitalLogger.instance.warning('Biometrics', 'No biometrics available while lock enabled; disabling lock');
      if (mounted) {
        setState(() {
          _locked = false;
          _authInProgress = false;
        });
      }
      await ref.read(settingsProvider.notifier).setBiometricLockEnabled(false);
      return;
    }

    final authenticated = await _biometricsService.authenticateForUnlock();

    if (mounted) {
      setState(() {
        _locked = !authenticated;
        _authInProgress = false;
      });
    }

    if (authenticated) {
      _lastSuccessfulUnlockAt = DateTime.now();
    }

    OrbitalLogger.instance.info(
      'Biometrics',
      authenticated ? 'App unlocked successfully' : 'App remains locked (authentication failed/canceled)',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      alignment: Alignment.topLeft,
      children: [
        widget.child,
        if (_locked)
          Material(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lock_rounded, size: 56),
                      const SizedBox(height: 16),
                      Text(
                        'Orbital is locked',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Authenticate with biometrics to continue.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _authInProgress ? null : _lockAndAuthenticate,
                        icon: const Icon(Icons.fingerprint_rounded),
                        label: Text(_authInProgress ? 'Checking...' : 'Unlock'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
