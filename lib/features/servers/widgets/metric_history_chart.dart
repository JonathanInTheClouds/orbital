import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

// ── MetricHistoryChart ────────────────────────────────────────────────────────

/// Rolling sparkline chart rendered via [CustomPainter].
///
/// Supports up to two data series (e.g. network RX + TX).
/// When [maxValue] is `null` the y-axis is auto-scaled to the maximum across
/// both series, with a minimum floor so the chart never collapses to a flat
/// line on zero data.
class MetricHistoryChart extends StatelessWidget {
  /// Primary series data points (required).
  final List<double> primary;

  /// Optional secondary series (e.g. TX when primary is RX).
  final List<double>? secondary;

  final Color primaryColor;
  final Color? secondaryColor;

  /// Explicit y-axis maximum. Pass `100` for percentage metrics.
  /// `null` → auto-scale.
  final double? maxValue;

  /// Whether to draw subtle horizontal grid lines at 25 / 50 / 75 %.
  final bool showGrid;

  const MetricHistoryChart({
    super.key,
    required this.primary,
    required this.primaryColor,
    this.secondary,
    this.secondaryColor,
    this.maxValue,
    this.showGrid = true,
  });

  @override
  Widget build(BuildContext context) {
    final gridColor = Theme.of(context).dividerColor;
    return CustomPaint(
      size: Size.infinite,
      painter: _SparklinePainter(
        primary: primary,
        secondary: secondary,
        primaryColor: primaryColor,
        secondaryColor: secondaryColor,
        maxValue: maxValue,
        showGrid: showGrid,
        gridColor: gridColor,
      ),
    );
  }
}

// ── _SparklinePainter ─────────────────────────────────────────────────────────

class _SparklinePainter extends CustomPainter {
  final List<double> primary;
  final List<double>? secondary;
  final Color primaryColor;
  final Color? secondaryColor;
  final double? maxValue;
  final bool showGrid;
  final Color gridColor;

  _SparklinePainter({
    required this.primary,
    required this.primaryColor,
    this.secondary,
    this.secondaryColor,
    this.maxValue,
    required this.showGrid,
    required this.gridColor,
  });

  // ── Helpers ───────────────────────────────────────────────────────────────

  double _computeMax() {
    if (maxValue != null) return maxValue!;
    double max = 1.0;
    if (primary.isNotEmpty) {
      max = math.max(max, primary.reduce(math.max));
    }
    if (secondary != null && secondary!.isNotEmpty) {
      max = math.max(max, secondary!.reduce(math.max));
    }
    return max;
  }

  List<Offset> _toPoints(List<double> values, Size size, double max) {
    final n = values.length;
    return List.generate(n, (i) {
      final x = n == 1 ? size.width / 2 : (i / (n - 1)) * size.width;
      final y = size.height - (values[i] / max).clamp(0.0, 1.0) * size.height;
      return Offset(x, y);
    });
  }

  // ── Draw methods ──────────────────────────────────────────────────────────

  void _drawGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = gridColor.withOpacity(0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    for (final pct in [0.25, 0.5, 0.75]) {
      final y = size.height * (1 - pct);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _drawEmptyState(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      Paint()
        ..color = gridColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round,
    );
  }

  Path _smoothPath(List<Offset> pts) {
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      final p = pts[i - 1];
      final c = pts[i];
      final cx = (p.dx + c.dx) / 2;
      path.cubicTo(cx, p.dy, cx, c.dy, c.dx, c.dy);
    }
    return path;
  }

  void _drawFill(Canvas canvas, Size size, List<Offset> pts, Color color) {
    if (pts.length < 2) return;
    final linePath = _smoothPath(pts);
    final fillPath = Path.from(linePath)
      ..lineTo(pts.last.dx, size.height)
      ..lineTo(pts.first.dx, size.height)
      ..close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withOpacity(0.28), color.withOpacity(0.01)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );
  }

  void _drawLine(Canvas canvas, List<Offset> pts, Color color) {
    if (pts.length < 2) return;
    canvas.drawPath(
      _smoothPath(pts),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _drawEndDot(Canvas canvas, Offset pt, Color color) {
    // Outer glow ring
    canvas.drawCircle(pt, 7, Paint()..color = color.withOpacity(0.18));
    // Solid dot
    canvas.drawCircle(pt, 3.5, Paint()..color = color);
    // White centre
    canvas.drawCircle(pt, 1.5, Paint()..color = Colors.white);
  }

  // ── paint ─────────────────────────────────────────────────────────────────

  @override
  void paint(Canvas canvas, Size size) {
    if (primary.isEmpty) {
      _drawEmptyState(canvas, size);
      return;
    }

    final max = _computeMax();
    final primaryPts = _toPoints(primary, size, max);

    if (showGrid) _drawGrid(canvas, size);

    // Draw secondary series first (behind primary)
    if (secondary != null && secondary!.isNotEmpty) {
      final secColor = secondaryColor ?? primaryColor.withOpacity(0.6);
      final secPts = _toPoints(secondary!, size, max);
      _drawFill(canvas, size, secPts, secColor);
      _drawLine(canvas, secPts, secColor);
      _drawEndDot(canvas, secPts.last, secColor);
    }

    // Draw primary series on top
    _drawFill(canvas, size, primaryPts, primaryColor);
    _drawLine(canvas, primaryPts, primaryColor);
    _drawEndDot(canvas, primaryPts.last, primaryColor);
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.primary != primary ||
      old.secondary != secondary ||
      old.primaryColor != primaryColor ||
      old.maxValue != maxValue ||
      old.gridColor != gridColor;
}
