import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/constants/app_constants.dart';
import '../data/database/app_database.dart';
import '../features/alerts/screens/alerts_screen.dart';
import '../features/docker/screens/docker_screen.dart';
import '../features/servers/screens/add_server_screen.dart';
import '../features/servers/screens/edit_server_screen.dart';
import '../features/servers/screens/server_detail_preview.dart';
import '../features/servers/screens/server_detail_screen.dart';
import '../features/servers/screens/servers_list_preview.dart';
import '../features/servers/screens/servers_screen.dart';
import '../features/settings/screens/settings_screen.dart';
import '../features/terminal/screens/terminal_screen.dart';
import '../core/screens/shell_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.servers,
    debugLogDiagnostics: false,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            ShellScreen(navigationShell: navigationShell),
        branches: [
          // ── Branch 0: Servers ───────────────────────────────────────────
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.servers,
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: ServersScreen()),
                routes: [
                  GoRoute(
                    path: 'add',
                    builder: (context, state) => const AddServerScreen(),
                  ),
                  GoRoute(
                    path: 'preview-list',
                    builder: (context, state) => const ServersListPreview(),
                  ),
                  GoRoute(
                    path: 'preview',
                    builder: (context, state) => const ServerDetailPreview(),
                  ),
                  GoRoute(
                    path: ':id',
                    builder: (context, state) => ServerDetailScreen(
                      serverId: state.pathParameters['id']!,
                    ),
                    routes: [
                      GoRoute(
                        path: 'edit',
                        builder: (context, state) {
                          final server = state.extra as Server;
                          return EditServerScreen(server: server);
                        },
                      ),
                      GoRoute(
                        path: 'terminal',
                        builder: (context, state) => TerminalScreen(
                          serverId: state.pathParameters['id']!,
                        ),
                      ),
                      GoRoute(
                        path: 'docker',
                        builder: (context, state) =>
                            DockerScreen(serverId: state.pathParameters['id']!),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),

          // ── Branch 1: Alerts ────────────────────────────────────────────
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.alerts,
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: AlertsScreen()),
              ),
            ],
          ),

          // ── Branch 2: Settings ──────────────────────────────────────────
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.settings,
                pageBuilder: (context, state) =>
                    const NoTransitionPage(child: SettingsScreen()),
                routes: [
                  GoRoute(
                    path: 'monitoring',
                    builder: (context, state) =>
                        const MonitoringSettingsScreen(),
                  ),
                  GoRoute(
                    path: 'thresholds',
                    builder: (context, state) =>
                        const ThresholdsSettingsScreen(),
                  ),
                  GoRoute(
                    path: 'relay',
                    builder: (context, state) => const RelaySettingsScreen(),
                  ),
                  GoRoute(
                    path: 'appearance',
                    builder: (context, state) =>
                        const AppearanceSettingsScreen(),
                  ),
                  GoRoute(
                    path: 'security',
                    builder: (context, state) =>
                        const SecuritySettingsScreen(),
                  ),
                  GoRoute(
                    path: 'developer',
                    builder: (context, state) =>
                        const DeveloperSettingsScreen(),
                  ),
                  GoRoute(
                    path: 'about',
                    builder: (context, state) => const AboutSettingsScreen(),
                  ),
                  GoRoute(
                    path: 'logs',
                    builder: (context, state) => const LogsScreen(),
                  ),
                  GoRoute(
                    path: 'session-logs',
                    builder: (context, state) => const SessionLogsScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
