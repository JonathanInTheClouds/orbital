import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../docker_models.dart';
import '../docker_provider.dart';

// ── DockerScreen ──────────────────────────────────────────────────────────────

class DockerScreen extends ConsumerStatefulWidget {
  final String serverId;

  const DockerScreen({super.key, required this.serverId});

  @override
  ConsumerState<DockerScreen> createState() => _DockerScreenState();
}

class _DockerScreenState extends ConsumerState<DockerScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  int get _id => int.parse(widget.serverId);

  late final _notifier = ref.read(dockerManagerProvider.notifier);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 1) {
        _notifier.refreshImages(_id);
      }
    });
    Future.microtask(() => _notifier.startPolling(_id));
  }

  @override
  void dispose() {
    _notifier.stopPolling(_id);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final docker = ref.watch(dockerProvider(_id));

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: _buildAppBar(docker),
      body: TabBarView(
        controller: _tabController,
        children: [
          _ContainersTab(serverId: _id, docker: docker),
          _ImagesTab(serverId: _id, docker: docker),
        ],
      ),
    );
  }

  AppBar _buildAppBar(DockerState docker) {
    return AppBar(
      backgroundColor: Theme.of(context).colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: IconButton(
        icon: Icon(
          Icons.arrow_back_ios_new_rounded,
          size: 20,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        onPressed: () => context.pop(),
      ),
      title: Row(
        children: [
          Icon(
            Icons.inventory_2_rounded,
            size: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Text(
            'Docker',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          if (docker.lastUpdated != null) ...[
            const SizedBox(width: 8),
            Text(
              _timeAgo(docker.lastUpdated!),
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
      actions: [
        if (docker.isLoading)
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          )
        else
          IconButton(
            icon: Icon(
              Icons.refresh_rounded,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            onPressed: () =>
                ref.read(dockerManagerProvider.notifier).refreshContainers(_id),
          ),
      ],
      bottom: TabBar(
        controller: _tabController,
        dividerColor: Colors.transparent,
        indicatorColor: Theme.of(context).colorScheme.primary,
        labelColor: Theme.of(context).colorScheme.primary,
        unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        tabs: [
          Tab(
            text: docker.containers.isEmpty
                ? 'Containers'
                : 'Containers (${docker.containers.length})',
          ),
          Tab(
            text: docker.images.isEmpty
                ? 'Images'
                : 'Images (${docker.images.length})',
          ),
        ],
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 10) return 'just now';
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }
}

// ── _ContainersTab ────────────────────────────────────────────────────────────

class _ContainersTab extends ConsumerWidget {
  final int serverId;
  final DockerState docker;

  const _ContainersTab({required this.serverId, required this.docker});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (docker.errorMessage != null && docker.containers.isEmpty) {
      return _ErrorState(
        message: docker.errorMessage!,
        onRetry: () => ref
            .read(dockerManagerProvider.notifier)
            .refreshContainers(serverId),
      );
    }

    if (docker.isLoading && docker.containers.isEmpty) {
      return Center(
        child: CircularProgressIndicator(
          color: Theme.of(context).colorScheme.primary,
          strokeWidth: 2,
        ),
      );
    }

    if (docker.containers.isEmpty) {
      return const _EmptyState(
        icon: Icons.inventory_2_outlined,
        message: 'No containers found',
        sub: 'Run docker ps -a to verify',
      );
    }

    final sorted = [...docker.containers]
      ..sort((a, b) {
        if (a.state.isRunning && !b.state.isRunning) return -1;
        if (!a.state.isRunning && b.state.isRunning) return 1;
        return a.name.compareTo(b.name);
      });

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.all(16),
      itemCount: sorted.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _ContainerCard(
        container: sorted[i],
        onTap: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Theme.of(context).colorScheme.surface,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          builder: (_) =>
              _ContainerDetailSheet(container: sorted[i], serverId: serverId),
        ),
      ),
    );
  }
}

// ── _ContainerCard ────────────────────────────────────────────────────────────

class _ContainerCard extends StatelessWidget {
  final DockerContainer container;
  final VoidCallback onTap;

  const _ContainerCard({required this.container, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
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
          boxShadow: Theme.of(context).brightness == Brightness.dark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _StateIndicator(state: container.state),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        container.name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        container.image,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontFamily: 'Menlo',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                _StateBadge(state: container.state, status: container.status),
              ],
            ),
            if (container.state.isRunning && container.cpuPercent != null) ...[
              const SizedBox(height: 10),
              Divider(
                height: 1,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white.withOpacity(0.08)
                    : Colors.black.withOpacity(0.08),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _StatPill(
                    label: 'CPU',
                    value: '${container.cpuPercent!.toStringAsFixed(1)}%',
                    color: OrbitalColors.cpu,
                  ),
                  const SizedBox(width: 8),
                  if (container.memPercent != null)
                    _StatPill(
                      label: 'MEM',
                      value: '${container.memPercent!.toStringAsFixed(1)}%',
                      color: OrbitalColors.memory,
                    ),
                  const SizedBox(width: 8),
                  if (container.pids != null)
                    _StatPill(
                      label: 'PIDs',
                      value: '${container.pids}',
                      color: OrbitalColors.textSecondary,
                    ),
                ],
              ),
            ],
            if (container.ports.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: container.ports.map((p) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).inputDecorationTheme.fillColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      p,
                      style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontFamily: 'Menlo',
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── _ContainerDetailSheet ─────────────────────────────────────────────────────

class _ContainerDetailSheet extends ConsumerStatefulWidget {
  final DockerContainer container;
  final int serverId;

  const _ContainerDetailSheet({
    required this.container,
    required this.serverId,
  });

  @override
  ConsumerState<_ContainerDetailSheet> createState() =>
      _ContainerDetailSheetState();
}

class _ContainerDetailSheetState extends ConsumerState<_ContainerDetailSheet> {
  String? _logs;
  bool _loadingLogs = false;
  bool _actionInProgress = false;

  @override
  void initState() {
    super.initState();
    _fetchLogs();
  }

  Future<void> _fetchLogs() async {
    setState(() => _loadingLogs = true);
    try {
      final logs = await ref
          .read(dockerManagerProvider.notifier)
          .fetchLogs(widget.serverId, widget.container.id);
      if (mounted) setState(() => _logs = logs);
    } catch (e) {
      if (mounted) setState(() => _logs = 'Error loading logs: $e');
    } finally {
      if (mounted) setState(() => _loadingLogs = false);
    }
  }

  Future<void> _runAction(Future<void> Function() action) async {
    setState(() => _actionInProgress = true);
    try {
      await action();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _actionInProgress = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final container = widget.container;
    final sid = widget.serverId;
    final notifier = ref.read(dockerManagerProvider.notifier);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 16),
              decoration: BoxDecoration(
                color: Theme.of(context).dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Row(
                children: [
                  _StateIndicator(state: container.state),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          container.name,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          container.shortId,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            fontFamily: 'Menlo',
                          ),
                        ),
                      ],
                    ),
                  ),
                  _StateBadge(state: container.state, status: container.status),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _actionInProgress
                  ? Center(
                      child: CircularProgressIndicator(
                        color: Theme.of(context).colorScheme.primary,
                        strokeWidth: 2,
                      ),
                    )
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          if (!container.state.isRunning)
                            _ActionButton(
                              label: 'Start',
                              icon: Icons.play_arrow_rounded,
                              color: OrbitalColors.online,
                              onTap: () => _runAction(
                                () =>
                                    notifier.startContainer(sid, container.id),
                              ),
                            ),
                          if (container.state.isRunning) ...[
                            _ActionButton(
                              label: 'Stop',
                              icon: Icons.stop_rounded,
                              color: OrbitalColors.warning,
                              onTap: () => _runAction(
                                () => notifier.stopContainer(sid, container.id),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _ActionButton(
                              label: 'Restart',
                              icon: Icons.refresh_rounded,
                              color: Theme.of(context).colorScheme.primary,
                              onTap: () => _runAction(
                                () => notifier.restartContainer(
                                  sid,
                                  container.id,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(width: 8),
                          _ActionButton(
                            label: 'Remove',
                            icon: Icons.delete_rounded,
                            color: OrbitalColors.danger,
                            onTap: () => _runAction(
                              () => notifier.removeContainer(
                                sid,
                                container.id,
                                force: container.state.isRunning,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _ActionButton(
                            label: 'Refresh Logs',
                            icon: Icons.refresh_rounded,
                            color: OrbitalColors.textSecondary,
                            onTap: _fetchLogs,
                          ),
                        ],
                      ),
                    ),
            ),
            Divider(
              height: 1,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white.withOpacity(0.08)
                  : Colors.black.withOpacity(0.08),
            ),
            Expanded(
              child: _loadingLogs
                  ? Center(
                      child: CircularProgressIndicator(
                        color: Theme.of(context).colorScheme.primary,
                        strokeWidth: 2,
                      ),
                    )
                  : _logs == null || _logs!.isEmpty
                  ? Center(
                      child: Text(
                        'No logs',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _logs!,
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontFamily: 'Menlo',
                          height: 1.5,
                        ),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

// ── _ImagesTab ────────────────────────────────────────────────────────────────

class _ImagesTab extends ConsumerWidget {
  final int serverId;
  final DockerState docker;

  const _ImagesTab({required this.serverId, required this.docker});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (docker.images.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _EmptyState(
              icon: Icons.layers_outlined,
              message: 'No images loaded',
              sub: 'Tap below to load',
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => ref
                  .read(dockerManagerProvider.notifier)
                  .refreshImages(serverId),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Load Images'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.primary,
                side: BorderSide(color: Theme.of(context).colorScheme.primary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.all(16),
      itemCount: docker.images.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _ImageCard(
        image: docker.images[i],
        onRemove: () => ref
            .read(dockerManagerProvider.notifier)
            .removeImage(serverId, docker.images[i].id),
      ),
    );
  }
}

// ── _ImageCard ────────────────────────────────────────────────────────────────

class _ImageCard extends StatelessWidget {
  final DockerImage image;
  final VoidCallback onRemove;

  const _ImageCard({required this.image, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white.withOpacity(0.08)
              : Colors.black.withOpacity(0.08),
        ),
        boxShadow: Theme.of(context).brightness == Brightness.dark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
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
              Icons.layers_rounded,
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
                  image.displayName,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                    fontFamily: 'Menlo',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${image.id.length >= 12 ? image.id.substring(0, 12) : image.id}  •  ${_formatSize(image.sizeBytes)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontFamily: 'Menlo',
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.delete_outline_rounded,
              size: 18,
              color: OrbitalColors.danger,
            ),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────

class _StateIndicator extends StatelessWidget {
  final DockerContainerState state;
  const _StateIndicator({required this.state});

  Color get _color => switch (state) {
    DockerContainerState.running => OrbitalColors.online,
    DockerContainerState.paused => OrbitalColors.warning,
    DockerContainerState.restarting => OrbitalColors.warning,
    DockerContainerState.exited ||
    DockerContainerState.dead => OrbitalColors.danger,
    _ => OrbitalColors.offline,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: _color, shape: BoxShape.circle),
    );
  }
}

class _StateBadge extends StatelessWidget {
  final DockerContainerState state;
  final String status;
  const _StateBadge({required this.state, required this.status});

  Color get _color => switch (state) {
    DockerContainerState.running => OrbitalColors.online,
    DockerContainerState.paused => OrbitalColors.warning,
    DockerContainerState.restarting => OrbitalColors.warning,
    DockerContainerState.exited ||
    DockerContainerState.dead => OrbitalColors.danger,
    _ => OrbitalColors.offline,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _color.withOpacity(0.3)),
      ),
      child: Text(
        state.name,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: _color,
        ),
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatPill({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: color.withOpacity(0.7),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w700,
              fontFamily: 'Menlo',
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String sub;
  const _EmptyState({
    required this.icon,
    required this.message,
    required this.sub,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: OrbitalColors.textMuted),
          const SizedBox(height: 16),
          Text(
            message,
            style: const TextStyle(
              fontSize: 16,
              color: OrbitalColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            sub,
            style: const TextStyle(
              fontSize: 13,
              color: OrbitalColors.textMuted,
              fontFamily: 'Menlo',
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: OrbitalColors.danger,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: OrbitalColors.textMuted,
                fontFamily: 'Menlo',
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.primary,
                side: BorderSide(color: Theme.of(context).colorScheme.primary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
