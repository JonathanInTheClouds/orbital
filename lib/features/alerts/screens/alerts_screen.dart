import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../models/alert_model.dart';
import '../providers/alert_provider.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// AlertsScreen
// ═══════════════════════════════════════════════════════════════════════════════

class AlertsScreen extends ConsumerWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(alertNotifierProvider);
    final unreadCount = ref.watch(unreadAlertCountProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          _AlertsAppBar(unreadCount: unreadCount),
          if (alerts.isEmpty)
            const SliverFillRemaining(child: _EmptyState())
          else
            _AlertsList(alerts: alerts),
        ],
      ),
    );
  }
}

// ── _AlertsAppBar ─────────────────────────────────────────────────────────────

class _AlertsAppBar extends ConsumerWidget {
  final int unreadCount;

  const _AlertsAppBar({required this.unreadCount});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(alertNotifierProvider.notifier);

    return SliverAppBar(
      pinned: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleSpacing: 20,
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Alerts',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
              letterSpacing: -0.3,
            ),
          ),
          if (unreadCount > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: OrbitalColors.danger,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$unreadCount',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ],
      ),
      actions: [
        _OverflowMenu(notifier: notifier),
        const SizedBox(width: 4),
      ],
    );
  }
}

// ── _OverflowMenu ─────────────────────────────────────────────────────────────

class _OverflowMenu extends StatelessWidget {
  final AlertNotifier notifier;

  const _OverflowMenu({required this.notifier});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_MenuAction>(
      onSelected: (action) => _handleAction(context, action),
      icon: Icon(
        Icons.more_horiz_rounded,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      itemBuilder: (_) => [
        _popupItem(
          context,
          value: _MenuAction.markAllRead,
          icon: Icons.done_all_rounded,
          label: 'Mark all as read',
          color: Theme.of(context).colorScheme.onSurface,
        ),
        _popupItem(
          context,
          value: _MenuAction.clearAll,
          icon: Icons.delete_sweep_rounded,
          label: 'Clear all',
          color: OrbitalColors.danger,
        ),
      ],
    );
  }

  PopupMenuEntry<_MenuAction> _popupItem(
    BuildContext context, {
    required _MenuAction value,
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleAction(BuildContext context, _MenuAction action) async {
    switch (action) {
      case _MenuAction.markAllRead:
        await notifier.markAllAsRead();
      case _MenuAction.clearAll:
        final confirmed = await _confirmClear(context);
        if (confirmed == true) await notifier.clearAll();
    }
  }

  Future<bool?> _confirmClear(BuildContext context) {
    return showModalBottomSheet<bool>(
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
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: OrbitalColors.danger.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.delete_sweep_rounded,
                size: 28,
                color: OrbitalColors.danger,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Clear All Alerts?',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: OrbitalColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'This will permanently remove all alerts from your history.',
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
                      'Clear All',
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
  }
}

enum _MenuAction { markAllRead, clearAll }

// ── _AlertsList ───────────────────────────────────────────────────────────────

class _AlertsList extends ConsumerWidget {
  final List<AlertModel> alerts;

  const _AlertsList({required this.alerts});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = _groupByDate(alerts);
    final items = _buildItems(groups);

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => items[index],
          childCount: items.length,
        ),
      ),
    );
  }

  List<Widget> _buildItems(Map<String, List<AlertModel>> groups) {
    final items = <Widget>[];
    for (final entry in groups.entries) {
      items.add(_DateHeader(label: entry.key));
      for (final alert in entry.value) {
        items.add(_DismissibleAlertCard(key: ValueKey(alert.id), alert: alert));
        items.add(const SizedBox(height: 8));
      }
    }
    if (items.isNotEmpty) items.removeLast();
    return items;
  }

  Map<String, List<AlertModel>> _groupByDate(List<AlertModel> alerts) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    final Map<String, List<AlertModel>> groups = {};
    for (final alert in alerts) {
      final d = alert.timestamp;
      final day = DateTime(d.year, d.month, d.day);
      final String label;
      if (day == today) {
        label = 'Today';
      } else if (day == yesterday) {
        label = 'Yesterday';
      } else {
        label = _formatDate(d);
      }
      groups.putIfAbsent(label, () => []).add(alert);
    }
    return groups;
  }

  String _formatDate(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}';
  }
}

// ── _DateHeader ───────────────────────────────────────────────────────────────

class _DateHeader extends StatelessWidget {
  final String label;

  const _DateHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color:
              Theme.of(context).textTheme.bodySmall?.color ??
              OrbitalColors.textMuted,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

// ── _DismissibleAlertCard ─────────────────────────────────────────────────────

class _DismissibleAlertCard extends ConsumerWidget {
  final AlertModel alert;

  const _DismissibleAlertCard({super.key, required this.alert});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dismissible(
      key: ValueKey(alert.id),
      direction: DismissDirection.endToStart,
      background: _SwipeBackground(),
      onDismissed: (_) {
        ref.read(alertNotifierProvider.notifier).dismissAlert(alert.id);
      },
      child: _AlertCard(alert: alert),
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 20),
      decoration: BoxDecoration(
        color: OrbitalColors.danger.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Icon(
        Icons.delete_rounded,
        color: OrbitalColors.danger,
        size: 22,
      ),
    );
  }
}

// ── _AlertCard ────────────────────────────────────────────────────────────────

class _AlertCard extends ConsumerWidget {
  final AlertModel alert;

  const _AlertCard({required this.alert});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final color = colorScheme.primary;
    final isDark = theme.brightness == Brightness.dark;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.08);

    return GestureDetector(
      onTap: () {
        if (!alert.isRead) {
          ref.read(alertNotifierProvider.notifier).markAsRead(alert.id);
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          // Uniform border — no multi-color border which breaks with borderRadius
          border: Border.all(color: borderColor),
        ),
        clipBehavior: Clip.hardEdge,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left accent strip — animates color when read/unread changes
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                width: 3,
                color: alert.isRead ? Colors.transparent : color,
              ),

              // Card body
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 13, 14, 13),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Metric icon badge
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          _metricIcon(alert.metric),
                          size: 19,
                          color: color,
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Text content
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Text(
                                    '${alert.metricLabel} threshold exceeded',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: alert.isRead
                                          ? FontWeight.w500
                                          : FontWeight.w700,
                                      color: colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _relativeTime(alert.timestamp),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: theme.textTheme.bodySmall?.color ??
                                        OrbitalColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                            if (alert.hasStructuredDetails) ...[
                              const SizedBox(height: 5),
                              Row(
                                children: [
                                  _MetricChip(
                                    label: '${alert.value.toStringAsFixed(1)}%',
                                    color: color,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'threshold ${alert.threshold.toStringAsFixed(0)}%',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color:
                                          theme.textTheme.bodySmall?.color ??
                                          OrbitalColors.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 5),
                            Text(
                              alert.displayServer,
                              style: TextStyle(
                                fontSize: 12,
                                color:
                                    theme.textTheme.bodySmall?.color ??
                                    OrbitalColors.textMuted,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),

                      // Unread dot
                      if (!alert.isRead)
                        Padding(
                          padding: const EdgeInsets.only(left: 8, top: 3),
                          child: Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _metricIcon(String metric) => switch (metric) {
    'cpu' => Icons.memory_rounded,
    'ram' => Icons.storage_rounded,
    'disk' => Icons.disc_full_rounded,
    _ => Icons.warning_amber_rounded,
  };

  String _relativeTime(DateTime timestamp) {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }
}

// ── _MetricChip ───────────────────────────────────────────────────────────────

class _MetricChip extends StatelessWidget {
  final String label;
  final Color color;

  const _MetricChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

// ── _EmptyState ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.notifications_none_rounded,
                size: 34,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No alerts yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurface,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Alerts appear here when a server\nexceeds a configured threshold.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color:
                    Theme.of(context).textTheme.bodySmall?.color ??
                    OrbitalColors.textMuted,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
