import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

// ── MetricGauge ───────────────────────────────────────────────────────────────

/// Animated arc gauge for a single metric (CPU, RAM, Disk, Network).
///
/// [percent] must be in the range 0.0–1.0.
/// [valueText] is displayed in the centre (e.g. "73%" or "2.4 MB/s").
/// [isAlert] switches the arc colour to [OrbitalColors.danger].
class MetricGauge extends StatelessWidget {
  final double percent;
  final String label;
  final String valueText;
  final String? subText;
  final Color color;
  final bool isAlert;

  const MetricGauge({
    super.key,
    required this.percent,
    required this.label,
    required this.valueText,
    this.subText,
    required this.color,
    this.isAlert = false,
  });

  @override
  Widget build(BuildContext context) {
    final displayColor = isAlert ? OrbitalColors.danger : color;
    final clamped = percent.clamp(0.0, 1.0);
    final muted =
        Theme.of(context).textTheme.bodySmall?.color ?? OrbitalColors.textMuted;
    final track =
        Theme.of(context).inputDecorationTheme.fillColor ??
        OrbitalColors.surfaceElevated;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: clamped),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeInOut,
      builder: (context, animated, _) {
        return SizedBox(
          width: 110,
          height: 110,
          child: CustomPaint(
            painter: _GaugePainter(
              value: animated,
              color: displayColor,
              trackColor: track,
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    valueText,
                    style: TextStyle(
                      fontSize: valueText.length > 6 ? 13 : 17,
                      fontWeight: FontWeight.w700,
                      color: clamped > 0 ? displayColor : muted,
                      height: 1.1,
                    ),
                  ),
                  if (subText != null) ...[
                    const SizedBox(height: 1),
                    Text(
                      subText!,
                      style: TextStyle(
                        fontSize: 9,
                        color: muted,
                        fontFamily: 'Menlo',
                      ),
                    ),
                  ],
                  const SizedBox(height: 3),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: muted,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── _GaugePainter ─────────────────────────────────────────────────────────────

class _GaugePainter extends CustomPainter {
  final double value; // 0.0 – 1.0 (animated)
  final Color color;
  final Color trackColor;

  // Arc geometry:
  //   Flutter canvas: 0° = 3 o'clock, positive = clockwise.
  //   We want a "speedometer" arc — start at ~7 o'clock (210°), sweep 240°.
  //   210° × π/180 ≈ 3.665 rad  |  240° × π/180 ≈ 4.189 rad
  static const _startAngle = 3.665; // 210°
  static const _sweepAngle = 4.189; // 240°

  const _GaugePainter({
    required this.value,
    required this.color,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 10;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // ── Track (background arc) ─────────────────────────────────────────────
    canvas.drawArc(
      rect,
      _startAngle,
      _sweepAngle,
      false,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round,
    );

    if (value <= 0) return;

    final progressSweep = _sweepAngle * value;

    // ── Glow (blur layer under the arc) ───────────────────────────────────
    canvas.drawArc(
      rect,
      _startAngle,
      progressSweep,
      false,
      Paint()
        ..color = color.withOpacity(0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 16
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // ── Progress arc ──────────────────────────────────────────────────────
    canvas.drawArc(
      rect,
      _startAngle,
      progressSweep,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round,
    );

    // ── Tip dot ──────────────────────────────────────────────────────────
    final tipAngle = _startAngle + progressSweep;
    final tipX = center.dx + radius * math.cos(tipAngle);
    final tipY = center.dy + radius * math.sin(tipAngle);
    canvas.drawCircle(Offset(tipX, tipY), 3.5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.value != value || old.color != color || old.trackColor != trackColor;
}
