import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A custom animated sapling that grows from seed → sprout → full plant
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
  // Stem growth
  late AnimationController _stemController;
  late Animation<double> _stemHeight;

  // Leaves appear one by one
  late AnimationController _leavesController;
  late Animation<double> _leaf1;
  late Animation<double> _leaf2;
  late Animation<double> _leaf3;
  late Animation<double> _leaf4;

  // Soil/pot appear
  late AnimationController _potController;
  late Animation<double> _potScale;

  // Gentle sway after full growth
  late AnimationController _swayController;
  late Animation<double> _sway;

  bool _isComplete = false;

  @override
  void initState() {
    super.initState();

    // Pot slides up first
    _potController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _potScale = CurvedAnimation(parent: _potController, curve: Curves.elasticOut);

    // Stem grows upward
    _stemController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _stemHeight = CurvedAnimation(parent: _stemController, curve: Curves.easeOut);

    // Leaves unfold in sequence
    _leavesController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _leaf1 = CurvedAnimation(
      parent: _leavesController,
      curve: const Interval(0.0, 0.3, curve: Curves.elasticOut),
    );
    _leaf2 = CurvedAnimation(
      parent: _leavesController,
      curve: const Interval(0.2, 0.5, curve: Curves.elasticOut),
    );
    _leaf3 = CurvedAnimation(
      parent: _leavesController,
      curve: const Interval(0.4, 0.7, curve: Curves.elasticOut),
    );
    _leaf4 = CurvedAnimation(
      parent: _leavesController,
      curve: const Interval(0.6, 1.0, curve: Curves.elasticOut),
    );

    // Gentle sway
    _swayController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );
    _sway = Tween<double>(begin: -0.03, end: 0.03).animate(
      CurvedAnimation(parent: _swayController, curve: Curves.easeInOut),
    );

    _runSequence();
  }

  Future<void> _runSequence() async {
    await Future.delayed(const Duration(milliseconds: 400));
    await _potController.forward();
    await Future.delayed(const Duration(milliseconds: 200));
    await _stemController.forward();
    await Future.delayed(const Duration(milliseconds: 100));
    await _leavesController.forward();
    await Future.delayed(const Duration(milliseconds: 300));
    _swayController.repeat(reverse: true);

    if (!_isComplete) {
      _isComplete = true;
      widget.onComplete?.call();
    }
  }

  @override
  void dispose() {
    _potController.dispose();
    _stemController.dispose();
    _leavesController.dispose();
    _swayController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _potScale,
        _stemHeight,
        _leaf1,
        _leaf2,
        _leaf3,
        _leaf4,
        _sway,
      ]),
      builder: (context, _) {
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: CustomPaint(
            painter: _SaplingPainter(
              potScale: _potScale.value,
              stemProgress: _stemHeight.value,
              leaf1: _leaf1.value,
              leaf2: _leaf2.value,
              leaf3: _leaf3.value,
              leaf4: _leaf4.value,
              sway: _sway.value,
            ),
          ),
        );
      },
    );
  }
}

class _SaplingPainter extends CustomPainter {
  final double potScale;
  final double stemProgress;
  final double leaf1;
  final double leaf2;
  final double leaf3;
  final double leaf4;
  final double sway;

  _SaplingPainter({
    required this.potScale,
    required this.stemProgress,
    required this.leaf1,
    required this.leaf2,
    required this.leaf3,
    required this.leaf4,
    required this.sway,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height;

    // === POT ===
    if (potScale > 0) {
      canvas.save();
      canvas.translate(cx, cy - 10);
      canvas.scale(potScale, potScale);
      canvas.translate(-cx, -(cy - 10));
      _drawPot(canvas, size, cx, cy);
      canvas.restore();
    }

    // === STEM + LEAVES ===
    if (stemProgress > 0) {
      canvas.save();
      // Apply gentle sway rotation from base
      canvas.translate(cx, cy - 60);
      canvas.rotate(sway);
      canvas.translate(-cx, -(cy - 60));
      _drawStemAndLeaves(canvas, size, cx, cy);
      canvas.restore();
    }
  }

  void _drawPot(Canvas canvas, Size size, double cx, double cy) {
    // Soil (dark brown oval)
    final soilPaint = Paint()..color = const Color(0xFF5C3D1E);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, cy - 58),
        width: size.width * 0.52,
        height: 16,
      ),
      soilPaint,
    );

    // Pot body (purple trapezoid)
    final potPaint = Paint()..color = AppColors.primary;
    final potPath = Path()
      ..moveTo(cx - size.width * 0.22, cy - 55)
      ..lineTo(cx - size.width * 0.28, cy - 10)
      ..quadraticBezierTo(cx, cy + 8, cx + size.width * 0.28, cy - 10)
      ..lineTo(cx + size.width * 0.22, cy - 55)
      ..close();
    canvas.drawPath(potPath, potPaint);

    // Pot rim
    final rimPaint = Paint()
      ..color = AppColors.primaryDark
      ..style = PaintingStyle.fill;
    final rimRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(cx, cy - 57),
        width: size.width * 0.5,
        height: 14,
      ),
      const Radius.circular(7),
    );
    canvas.drawRRect(rimRect, rimPaint);

    // Pot highlight
    final hlPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..style = PaintingStyle.fill;
    final hlPath = Path()
      ..moveTo(cx - size.width * 0.18, cy - 52)
      ..lineTo(cx - size.width * 0.22, cy - 20)
      ..lineTo(cx - size.width * 0.12, cy - 20)
      ..lineTo(cx - size.width * 0.08, cy - 52)
      ..close();
    canvas.drawPath(hlPath, hlPaint);
  }

  void _drawStemAndLeaves(Canvas canvas, Size size, double cx, double cy) {
    final maxStemHeight = size.height * 0.55;
    final stemTop = (cy - 60) - maxStemHeight * stemProgress;

    // === STEM ===
    final stemPaint = Paint()
      ..color = const Color(0xFF4ADE80)
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final stemPath = Path()
      ..moveTo(cx, cy - 60)
      ..cubicTo(
        cx + 8, cy - 60 - maxStemHeight * 0.3 * stemProgress,
        cx - 6, cy - 60 - maxStemHeight * 0.6 * stemProgress,
        cx, stemTop,
      );
    canvas.drawPath(stemPath, stemPaint);

    if (stemProgress < 0.1) return;

    // === LEAVES ===
    // Leaf 1 – lower left
    final leaf1Y = cy - 60 - maxStemHeight * 0.25 * stemProgress;
    _drawLeaf(canvas, cx - 4, leaf1Y, leaf1, -0.6, false, const Color(0xFF22C55E));

    // Leaf 2 – lower right
    final leaf2Y = cy - 60 - maxStemHeight * 0.40 * stemProgress;
    _drawLeaf(canvas, cx + 2, leaf2Y, leaf2, 0.5, true, const Color(0xFF16A34A));

    // Leaf 3 – mid left
    final leaf3Y = cy - 60 - maxStemHeight * 0.62 * stemProgress;
    _drawLeaf(canvas, cx - 2, leaf3Y, leaf3, -0.7, false, const Color(0xFF4ADE80));

    // Leaf 4 – top (heart-shaped top leaf)
    if (leaf4 > 0) {
      _drawTopLeaf(canvas, cx, stemTop, leaf4);
    }
  }

  void _drawLeaf(Canvas canvas, double x, double y, double progress,
      double angle, bool flipX, Color color) {
    if (progress <= 0) return;
    final leafLen = 40.0 * progress;
    final leafWidth = 20.0 * progress;

    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(angle);
    if (flipX) canvas.scale(-1, 1);

    final leafPaint = Paint()..color = color;
    final leafPath = Path()
      ..moveTo(0, 0)
      ..cubicTo(-leafWidth, -leafLen * 0.4, -leafWidth * 0.8, -leafLen * 0.8,
          0, -leafLen)
      ..cubicTo(
          leafWidth * 0.4, -leafLen * 0.8, leafWidth * 0.2, -leafLen * 0.4, 0, 0)
      ..close();
    canvas.drawPath(leafPath, leafPaint);

    // Leaf vein
    final veinPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(const Offset(0, 0), Offset(0, -leafLen * 0.8), veinPaint);

    canvas.restore();
  }

  void _drawTopLeaf(Canvas canvas, double x, double y, double progress) {
    final r = 18.0 * progress;
    canvas.save();
    canvas.translate(x, y);

    // Top two big leaves
    final paint = Paint()..color = const Color(0xFF22C55E);

    // Left big leaf
    final leftPath = Path()
      ..moveTo(0, 0)
      ..cubicTo(-r * 2, -r, -r * 2.5, -r * 2.5, -r * 0.5, -r * 2.8)
      ..cubicTo(-r * 0.2, -r * 2, -r * 0.5, -r, 0, 0)
      ..close();
    canvas.drawPath(leftPath, paint);

    // Right big leaf
    final rightPath = Path()
      ..moveTo(0, 0)
      ..cubicTo(r * 2, -r, r * 2.5, -r * 2.5, r * 0.5, -r * 2.8)
      ..cubicTo(r * 0.2, -r * 2, r * 0.5, -r, 0, 0)
      ..close();
    canvas.drawPath(rightPath, paint);

    // Center top shoot
    final shootPaint = Paint()..color = const Color(0xFF4ADE80);
    final shootPath = Path()
      ..moveTo(0, 0)
      ..cubicTo(-r * 0.3, -r, -r * 0.2, -r * 2.5, 0, -r * 3)
      ..cubicTo(r * 0.2, -r * 2.5, r * 0.3, -r, 0, 0)
      ..close();
    canvas.drawPath(shootPath, shootPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_SaplingPainter old) => true;
}
