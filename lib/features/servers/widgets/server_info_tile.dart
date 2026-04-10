import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

// ── ServerInfoTile ────────────────────────────────────────────────────────────

/// A single row in the "System" info section of the server detail screen.
///
/// Displays an icon badge, a muted label above, and a value below.
/// Set [isMonospace] to `true` for kernel versions, IP addresses, etc.
class ServerInfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? iconColor;
  final Color? valueColor;
  final bool isMonospace;

  /// If `true` a [Divider] is prepended above this tile.
  final bool showTopDivider;

  const ServerInfoTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.iconColor,
    this.valueColor,
    this.isMonospace = false,
    this.showTopDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showTopDivider)
          const Divider(height: 1, indent: 60, endIndent: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(
            children: [
              // Icon badge
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: (iconColor ??
                          (Theme.of(context).textTheme.bodySmall?.color ??
                              OrbitalColors.textMuted))
                      .withOpacity(0.1),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  icon,
                  size: 17,
                  color:
                      iconColor ?? Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              // Label + value
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color:
                            Theme.of(context).textTheme.bodySmall?.color ??
                            OrbitalColors.textMuted,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color:
                            valueColor ?? Theme.of(context).colorScheme.onSurface,
                        fontFamily: isMonospace ? 'Menlo' : null,
                        letterSpacing: isMonospace ? 0.3 : null,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
