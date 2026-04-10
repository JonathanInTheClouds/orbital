import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/database/app_database.dart';
import '../../../data/models/server_model.dart';
import '../../../data/repositories/server_repository.dart';
import '../../../data/settings/settings_repository.dart';
import '../../../ssh/ssh_connection_manager.dart';
import '../../../ssh/ssh_models.dart';
import '../widgets/server_card.dart';
import '../widgets/servers_empty_state.dart';

// ── Sort + Filter enums ───────────────────────────────────────────────────────

enum ServerSortOrder {
  nameAsc('Name A→Z'),
  nameDesc('Name Z→A'),
  onlineFirst('Online First'),
  dateAdded('Date Added');

  final String label;
  const ServerSortOrder(this.label);
}

enum ServerFilter {
  all('All'),
  onlineOnly('Online Only'),
  offlineOnly('Offline Only');

  final String label;
  const ServerFilter(this.label);
}

// ── ServersScreen ─────────────────────────────────────────────────────────────

class ServersScreen extends ConsumerStatefulWidget {
  const ServersScreen({super.key});

  @override
  ConsumerState<ServersScreen> createState() => _ServersScreenState();
}

class _ServersScreenState extends ConsumerState<ServersScreen> {
  bool _searchActive = false;
  String _searchQuery = '';
  ServerSortOrder _sortOrder = ServerSortOrder.onlineFirst;
  ServerFilter _filter = ServerFilter.all;

  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  // ── Search ────────────────────────────────────────────────────────────────

  void _openSearch() {
    setState(() => _searchActive = true);
    Future.delayed(const Duration(milliseconds: 50), () {
      _searchFocusNode.requestFocus();
    });
  }

  void _closeSearch() {
    setState(() {
      _searchActive = false;
      _searchQuery = '';
      _searchController.clear();
    });
    _searchFocusNode.unfocus();
  }

  // ── Sort / Filter sheet ───────────────────────────────────────────────────

  Future<void> _showSortFilterSheet() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _SortFilterSheet(
        sortOrder: _sortOrder,
        filter: _filter,
        onChanged: (sort, filter) {
          setState(() {
            _sortOrder = sort;
            _filter = filter;
          });
        },
      ),
    );
  }

  // ── List processing ───────────────────────────────────────────────────────

  List<Server> _processServers(List<Server> servers) {
    // 1. Search filter
    var result = servers.where((s) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return s.displayName.toLowerCase().contains(q) ||
          s.host.toLowerCase().contains(q);
    }).toList();

    // 2. Status filter — needs connection state
    if (_filter != ServerFilter.all) {
      result = result.where((s) {
        final connAsync = ref.read(serverConnectionProvider(s));
        final isOnline =
            connAsync.asData?.value?.status == ConnectionStatus.connected;
        return _filter == ServerFilter.onlineOnly ? isOnline : !isOnline;
      }).toList();
    }

    // 3. Sort
    result.sort((a, b) {
      switch (_sortOrder) {
        case ServerSortOrder.nameAsc:
          return a.displayName.compareTo(b.displayName);
        case ServerSortOrder.nameDesc:
          return b.displayName.compareTo(a.displayName);
        case ServerSortOrder.onlineFirst:
          final aOnline =
              ref.read(serverConnectionProvider(a)).asData?.value?.status ==
              ConnectionStatus.connected;
          final bOnline =
              ref.read(serverConnectionProvider(b)).asData?.value?.status ==
              ConnectionStatus.connected;
          if (aOnline && !bOnline) return -1;
          if (!aOnline && bOnline) return 1;
          return a.displayName.compareTo(b.displayName);
        case ServerSortOrder.dateAdded:
          return b.createdAt.compareTo(a.createdAt);
      }
    });

    return result;
  }

  @override
  Widget build(BuildContext context) {
    final serversAsync = ref.watch(serversProvider);

    final hasServers = serversAsync.maybeWhen(
      data: (servers) => servers.isNotEmpty,
      orElse: () => false,
    );

    // Active filter/sort badge
    final hasActiveFilter =
        _filter != ServerFilter.all ||
        _sortOrder != ServerSortOrder.onlineFirst;

    return Scaffold(
      body: CustomScrollView(
        primary: false,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          _buildAppBar(hasActiveFilter),
          if (_searchActive) _buildSearchBar(),
          serversAsync.when(
            data: (servers) {
              if (servers.isEmpty) {
                return const SliverFillRemaining(child: ServersEmptyState());
              }
              final processed = _processServers(servers);
              if (processed.isEmpty) {
                return SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.search_off_rounded,
                          size: 48,
                          color:
                              Theme.of(context).textTheme.bodySmall?.color ??
                              OrbitalColors.textMuted,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _searchQuery.isNotEmpty
                              ? 'No servers match "$_searchQuery"'
                              : 'No servers match the current filter',
                          style: TextStyle(
                            color:
                                Theme.of(context).textTheme.bodySmall?.color ??
                                OrbitalColors.textMuted,
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                );
              }
              return _buildServerList(processed);
            },
            loading: () => const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => SliverFillRemaining(
              child: Center(
                child: Text(
                  'Error: $e',
                  style: const TextStyle(color: OrbitalColors.danger),
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: hasServers ? _buildFAB() : null,
    );
  }

  // ── AppBar ────────────────────────────────────────────────────────────────

  SliverAppBar _buildAppBar(bool hasActiveFilter) {
    final showPreview = ref.watch(
      settingsProvider.select((s) => s.showPreviewTools),
    );
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
          'Orbital',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurface,
            letterSpacing: -0.5,
          ),
        ),
        background: Container(color: Theme.of(context).scaffoldBackgroundColor),
      ),
      leading: showPreview
          ? Tooltip(
              message: 'Preview UI',
              child: IconButton(
                icon: Icon(
                  Icons.science_rounded,
                  color:
                      Theme.of(context).textTheme.bodySmall?.color ??
                      OrbitalColors.textMuted,
                  size: 22,
                ),
                onPressed: () => context.push('/servers/preview-list'),
              ),
            )
          : null,
      actions: [
        IconButton(
          icon: Icon(
            _searchActive ? Icons.search_off_rounded : Icons.search_rounded,
            color: _searchActive
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          onPressed: _searchActive ? _closeSearch : _openSearch,
        ),
        Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              icon: Icon(
                Icons.tune_rounded,
                color: hasActiveFilter
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              onPressed: _showSortFilterSheet,
            ),
            if (hasActiveFilter)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  // ── Search bar sliver ─────────────────────────────────────────────────────

  Widget _buildSearchBar() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          onChanged: (v) => setState(() => _searchQuery = v),
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 15,
          ),
          decoration: InputDecoration(
            hintText: 'Search servers…',
            prefixIcon: Icon(
              Icons.search_rounded,
              size: 18,
              color:
                  Theme.of(context).textTheme.bodySmall?.color ??
                  OrbitalColors.textMuted,
            ),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: Icon(
                      Icons.clear_rounded,
                      size: 18,
                      color:
                          Theme.of(context).textTheme.bodySmall?.color ??
                          OrbitalColors.textMuted,
                    ),
                    onPressed: () => setState(() {
                      _searchQuery = '';
                      _searchController.clear();
                    }),
                  )
                : null,
          ),
          textInputAction: TextInputAction.search,
        ),
      ),
    );
  }

  // ── Server list ───────────────────────────────────────────────────────────

  Widget _buildServerList(List<Server> servers) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          final server = servers[index];
          return Dismissible(
            key: ValueKey(server.id),
            direction: DismissDirection.endToStart,
            dismissThresholds: const {DismissDirection.endToStart: 0.15},
            movementDuration: const Duration(milliseconds: 400),
            resizeDuration: const Duration(milliseconds: 250),
            crossAxisEndOffset: 0.05,
            confirmDismiss: (_) => _confirmDelete(server),
            onDismissed: (_) => _deleteServer(server),
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 24),
              decoration: BoxDecoration(
                color: OrbitalColors.danger.withOpacity(0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: OrbitalColors.danger.withOpacity(0.3),
                ),
              ),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.delete_rounded,
                    color: OrbitalColors.danger,
                    size: 24,
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Delete',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: OrbitalColors.danger,
                    ),
                  ),
                ],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ServerCard(
                server: server,
                onTap: () => context.push('/servers/${server.id}'),
              ),
            ),
          );
        }, childCount: servers.length),
      ),
    );
  }

  // ── Delete flow ───────────────────────────────────────────────────────────

  Future<bool> _confirmDelete(Server server) async {
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
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: OrbitalColors.danger.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.delete_rounded,
                color: OrbitalColors.danger,
                size: 26,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Delete "${server.displayName}"?',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'The server and its stored credentials will be\npermanently removed. This cannot be undone.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color:
                    Theme.of(context).textTheme.bodySmall?.color ??
                    OrbitalColors.textMuted,
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
                      foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
                      side: BorderSide(
                        color: Theme.of(context).dividerColor,
                      ),
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
                      'Delete',
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
    return confirmed ?? false;
  }

  Future<void> _deleteServer(Server server) async {
    await ref.read(sshManagerProvider).disconnect(server.id);
    await ref.read(serverRepositoryProvider).deleteServer(server.id);
  }

  // ── FAB ───────────────────────────────────────────────────────────────────

  Widget _buildFAB() {
    return FloatingActionButton.extended(
      onPressed: () => context.push('/servers/add'),
      backgroundColor: Theme.of(context).colorScheme.primary,
      foregroundColor: Colors.white,
      elevation: 0,
      icon: const Icon(Icons.add_rounded),
      label: const Text(
        'Add Server',
        style: TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ── _SortFilterSheet ──────────────────────────────────────────────────────────

class _SortFilterSheet extends StatefulWidget {
  final ServerSortOrder sortOrder;
  final ServerFilter filter;
  final void Function(ServerSortOrder, ServerFilter) onChanged;

  const _SortFilterSheet({
    required this.sortOrder,
    required this.filter,
    required this.onChanged,
  });

  @override
  State<_SortFilterSheet> createState() => _SortFilterSheetState();
}

class _SortFilterSheetState extends State<_SortFilterSheet> {
  late ServerSortOrder _sort;
  late ServerFilter _filter;

  @override
  void initState() {
    super.initState();
    _sort = widget.sortOrder;
    _filter = widget.filter;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Sort section
            Text(
              'SORT',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color:
                    Theme.of(context).textTheme.bodySmall?.color ??
                    OrbitalColors.textMuted,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            ...ServerSortOrder.values.map(
              (order) => _OptionTile(
                label: order.label,
                selected: _sort == order,
                onTap: () {
                  setState(() => _sort = order);
                  widget.onChanged(_sort, _filter);
                },
              ),
            ),

            const SizedBox(height: 20),

            // Filter section
            Text(
              'FILTER',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color:
                    Theme.of(context).textTheme.bodySmall?.color ??
                    OrbitalColors.textMuted,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            ...ServerFilter.values.map(
              (filter) => _OptionTile(
                label: filter.label,
                selected: _filter == filter,
                onTap: () {
                  setState(() => _filter = filter);
                  widget.onChanged(_sort, _filter);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _OptionTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            if (selected)
              Icon(
                Icons.check_rounded,
                color: Theme.of(context).colorScheme.primary,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}
