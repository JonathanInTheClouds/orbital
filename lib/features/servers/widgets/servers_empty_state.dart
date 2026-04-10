import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';

class ServersEmptyState extends StatelessWidget {
  const ServersEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildIcon(context),
          const SizedBox(height: 24),
          Text(
            'No servers yet',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Add your first server to start monitoring\nCPU, memory, disk, and more in real time.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: Theme.of(context).textTheme.bodySmall?.color,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 36),
          ElevatedButton.icon(
            onPressed: () => context.push('/servers/add'),
            icon: const Icon(Icons.add_rounded, size: 20),
            label: const Text('Add Your First Server'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildIcon(BuildContext context) {
    final tint = Theme.of(context).colorScheme.primary;
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        color: tint.withOpacity(0.12),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: tint.withOpacity(0.2),
          width: 1.5,
        ),
      ),
      child: Icon(
        Icons.dns_rounded,
        size: 40,
        color: tint,
      ),
    );
  }
}
