// SaplingAnimation — Day 13
// Strict progressive drawing: seed → sprout → plant
// NO scale animation. NO fade animation.
// Uses PathMetrics for stem growth + progressive leaf drawing.

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class SaplingAnimation extends StatefulWidget {
  final double size;
  final VoidCallback? onComplete;

  const SaplingAnimation({
    super.key,
    this.size = 280,
    this.onComplete,
  }); 

  @override
  State<SaplingAnimation> createState() => SaplingAnimationState();
}

class SaplingAnimationState extends State<SaplingAnimation>
    with TickerProviderStateMixin {
  // Phase 1 — seed hatches (0 → 1)
  late AnimationController _seedCtrl;
  late Animation<double> _seedProgress;

  // Phase 2 — stem draws upward (0 → 1)
  late AnimationController _stemCtrl;
  late Animation<double> _stemProgress;

  // Phase 3 — leaves draw in sequence (0 → 1 each)
  late AnimationController _leavesCtrl;
  late Animation<double> _leaf1;
  late Animation<double> _leaf2;
  late Animation<double> _leaf3;
  late Animation<double> _leaf4;

  // Gentle sway after complete (idle loop)
  late AnimationController _swayCtrl;
  late Animation<double> _sway;

  bool _complete = false;

  @override
  void initState() {
    super.initState();

    // Seed phase — the pot + soil + seed dot grows via path drawing
    _seedCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _seedProgress = CurvedAnimation(parent: _seedCtrl, curve: Curves.easeOut);

    // Stem phase — path is drawn progressively via PathMetrics
    _stemCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400));
    _stemProgress = CurvedAnimation(parent: _stemCtrl, curve: Curves.easeInOut);

    // Leaves phase — each leaf drawn from base to tip sequentially
    _leavesCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2200));
    _leaf1 = CurvedAnimation(
        parent: _leavesCtrl,
        curve: const Interval(0.00, 0.28, curve: Curves.easeOut));
    _leaf2 = CurvedAnimation(
        parent: _leavesCtrl,
        curve: const Interval(0.22, 0.50, curve: Curves.easeOut));
    _leaf3 = CurvedAnimation(
        parent: _leavesCtrl,
        curve: const Interval(0.44, 0.72, curve: Curves.easeOut));
    _leaf4 = CurvedAnimation(
        parent: _leavesCtrl,
        curve: const Interval(0.66, 1.00, curve: Curves.easeOut));

    // Sway — gentle sine via repeated animation
    _swayCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2800));
    _sway = Tween<double>(begin: -0.025, end: 0.025)
        .animate(CurvedAnimation(parent: _swayCtrl, curve: Curves.easeInOut));

    _runSequence();
  }

  Future<void> _runSequence() async {
    await Future.delayed(const Duration(milliseconds: 300));

    // Seed / pot appears via progressive draw
    await _seedCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 200));

    // Stem grows upward
    await _stemCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 100));

    // Leaves unfold
    await _leavesCtrl.forward();

    // Start sway loop
    _swayCtrl.repeat(reverse: true);

    if (!_complete) {
      _complete = true;
      widget.onComplete?.call();
    }
  }

  @override
  void dispose() {
    _seedCtrl.dispose();
    _stemCtrl.dispose();
    _leavesCtrl.dispose();
    _swayCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _seedProgress,
        _stemProgress,
        _leaf1,
        _leaf2,
        _leaf3,
        _leaf4,
        _sway,
      ]),
      builder: (_, __) => SizedBox(
        width: widget.size,
        height: widget.size,
        child: CustomPaint(
          painter: _SaplingPainter(
            seedProgress: _seedProgress.value,
            stemProgress: _stemProgress.value,
            leaf1: _leaf1.value,
            leaf2: _leaf2.value,
            leaf3: _leaf3.value,
            leaf4: _leaf4.value,
            sway: _sway.value,
          ),
        ),
      ),
    );
  }
}

// ── Painter ───────────────────────────────────────────────────────────────

class _SaplingPainter extends CustomPainter {
  final double seedProgress;
  final double stemProgress;
  final double leaf1, leaf2, leaf3, leaf4;
  final double sway;

  const _SaplingPainter({
    required this.seedProgress,
    required this.stemProgress,
    required this.leaf1,
    required this.leaf2,
    required this.leaf3,
    required this.leaf4,
    required this.sway,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (seedProgress <= 0) return;

    final cx = size.width / 2;
    final cy = size.height;

    // ── SEED PHASE — pot + soil drawn progressively ──────────────────
    _drawPot(canvas, size, cx, cy, seedProgress);

    if (stemProgress <= 0 && leaf1 <= 0) return;

    // ── STEM + LEAVES — apply gentle sway ────────────────────────────
    canvas.save();
    canvas.translate(cx, cy - 58);
    canvas.rotate(sway);
    canvas.translate(-cx, -(cy - 58));

    _drawStem(canvas, size, cx, cy, stemProgress);

    if (stemProgress > 0.15) {
      _drawLeaves(canvas, size, cx, cy);
    }

    canvas.restore();
  }

  // ── POT — drawn by progressively clipping a vertical rect ──────────
  void _drawPot(Canvas canvas, Size size, double cx, double cy, double p) {
    final potH = size.height * 0.22; // total pot height
    final drawn = potH * p; // how much is revealed top-to-bottom

    canvas.save();
    // Clip: reveal from bottom up
    canvas.clipRect(Rect.fromLTRB(0, cy - drawn, size.width, cy + 20));

    // Soil oval
    final soilPaint = Paint()..color = const Color(0xFF5C3D1E);
    canvas.drawOval(
        Rect.fromCenter(
            center: Offset(cx, cy - 58), width: size.width * 0.52, height: 16),
        soilPaint);

    // Pot body (trapezoid)
    final potPaint = Paint()..color = AppColors.primary;
    final potPath = Path()
      ..moveTo(cx - size.width * 0.22, cy - 55)
      ..lineTo(cx - size.width * 0.28, cy - 10)
      ..quadraticBezierTo(cx, cy + 8, cx + size.width * 0.28, cy - 10)
      ..lineTo(cx + size.width * 0.22, cy - 55)
      ..close();
    canvas.drawPath(potPath, potPaint);

    // Rim
    final rimPaint = Paint()..color = AppColors.primaryDark;
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(cx, cy - 57),
                width: size.width * 0.5,
                height: 14),
            const Radius.circular(7)),
        rimPaint);

    // Highlight stripe
    final hlPaint = Paint()..color = Colors.white.withValues(alpha: 0.18);
    final hlPath = Path()
      ..moveTo(cx - size.width * 0.18, cy - 52)
      ..lineTo(cx - size.width * 0.22, cy - 20)
      ..lineTo(cx - size.width * 0.12, cy - 20)
      ..lineTo(cx - size.width * 0.08, cy - 52)
      ..close();
    canvas.drawPath(hlPath, hlPaint);

    // Seed dot (visible only in early phase)
    if (stemProgress < 0.05) {
      final seedPaint = Paint()..color = const Color(0xFF8B5E3C);
      canvas.drawCircle(Offset(cx, cy - 66), 5 * p, seedPaint);
    }

    canvas.restore();
  }

  // ── STEM — drawn via PathMetrics (true progressive draw) ─────────────
  void _drawStem(Canvas canvas, Size size, double cx, double cy, double p) {
    if (p <= 0) return;

    final maxH = size.height * 0.55;
    final stemTop = (cy - 60) - maxH;

    // Full bezier stem path
    final fullPath = Path()
      ..moveTo(cx, cy - 60)
      ..cubicTo(cx + 10, cy - 60 - maxH * 0.28, cx - 8, cy - 60 - maxH * 0.62,
          cx, stemTop);

    // Extract only the drawn portion using PathMetrics
    final metrics = fullPath.computeMetrics().first;
    final drawnLen = metrics.length * p;
    final drawnPath = metrics.extractPath(0, drawnLen);

    final stemPaint = Paint()
      ..color = const Color(0xFF4ADE80)
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawPath(drawnPath, stemPaint);
  }

  // ── LEAVES — each drawn from base to tip progressively ─────────────
  void _drawLeaves(Canvas canvas, Size size, double cx, double cy) {
    final maxH = size.height * 0.55;
    final stemTop = (cy - 60) - maxH;

    // Leaf positions along stem (fractions of stem height)
    final l1Y = (cy - 60) - maxH * 0.28 * stemProgress;
    final l2Y = (cy - 60) - maxH * 0.45 * stemProgress;
    final l3Y = (cy - 60) - maxH * 0.65 * stemProgress;

    _progressiveLeaf(
        canvas, cx - 4, l1Y, leaf1, -0.6, false, const Color(0xFF22C55E));
    _progressiveLeaf(
        canvas, cx + 2, l2Y, leaf2, 0.5, true, const Color(0xFF16A34A));
    _progressiveLeaf(
        canvas, cx - 2, l3Y, leaf3, -0.7, false, const Color(0xFF4ADE80));

    if (leaf4 > 0) {
      _progressiveTopLeaf(canvas, cx, stemTop, leaf4);
    }
  }

  /// Draws a leaf from base toward tip using PathMetrics (true progressive draw)
  void _progressiveLeaf(Canvas canvas, double x, double y, double progress,
      double angle, bool flipX, Color color) {
    if (progress <= 0) return;

    const leafLen = 42.0;
    const leafWidth = 18.0;

    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(angle);
    if (flipX) canvas.scale(-1, 1);

    // Full leaf outline path
    final leafPath = Path()
      ..moveTo(0, 0)
      ..cubicTo(-leafWidth, -leafLen * 0.4, -leafWidth * 0.8, -leafLen * 0.8, 0,
          -leafLen)
      ..cubicTo(leafWidth * 0.4, -leafLen * 0.8, leafWidth * 0.2,
          -leafLen * 0.4, 0, 0)
      ..close();

    // Draw solid fill at current progress by clipping
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(
        -leafWidth * 1.5, -leafLen * progress, leafWidth * 1.5, 0));
    canvas.drawPath(leafPath, Paint()..color = color);
    canvas.restore();

    // Vein (only if leaf is sufficiently drawn)
    if (progress > 0.2) {
      final veinLen = leafLen * progress * 0.8;
      canvas.drawLine(
          const Offset(0, 0),
          Offset(0, -veinLen),
          Paint()
            ..color = Colors.white.withValues(alpha: 0.28)
            ..strokeWidth = 1.2
            ..style = PaintingStyle.stroke);
    }

    canvas.restore();
  }

  /// Top two-wing leaf drawn progressively
  void _progressiveTopLeaf(Canvas canvas, double x, double y, double progress) {
    if (progress <= 0) return;
    const r = 18.0;

    canvas.save();
    canvas.translate(x, y);

    // Clip to reveal from center downward → upward
    canvas.clipRect(Rect.fromLTRB(-r * 3, -r * 3 * progress, r * 3, 0));

    final paint = Paint()..color = const Color(0xFF22C55E);

    // Left wing
    canvas.drawPath(
        Path()
          ..moveTo(0, 0)
          ..cubicTo(-r * 2, -r, -r * 2.5, -r * 2.5, -r * 0.5, -r * 2.8)
          ..cubicTo(-r * 0.2, -r * 2, -r * 0.5, -r, 0, 0)
          ..close(),
        paint);

    // Right wing
    canvas.drawPath(
        Path()
          ..moveTo(0, 0)
          ..cubicTo(r * 2, -r, r * 2.5, -r * 2.5, r * 0.5, -r * 2.8)
          ..cubicTo(r * 0.2, -r * 2, r * 0.5, -r, 0, 0)
          ..close(),
        paint);

    // Center shoot
    canvas.drawPath(
        Path()
          ..moveTo(0, 0)
          ..cubicTo(-r * 0.3, -r, -r * 0.2, -r * 2.5, 0, -r * 3)
          ..cubicTo(r * 0.2, -r * 2.5, r * 0.3, -r, 0, 0)
          ..close(),
        Paint()..color = const Color(0xFF4ADE80));

    canvas.restore();
  }

  @override
  bool shouldRepaint(_SaplingPainter old) =>
      old.seedProgress != seedProgress ||
      old.stemProgress != stemProgress ||
      old.leaf1 != leaf1 ||
      old.leaf2 != leaf2 ||
      old.leaf3 != leaf3 ||
      old.leaf4 != leaf4 ||
      old.sway != sway;
}
