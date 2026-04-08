import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class YourTreeScreen extends StatelessWidget {
  const YourTreeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Streak Badge ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(50),
              boxShadow: const [
                BoxShadow(
                  color: AppColors.shadow,
                  blurRadius: 8,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.local_fire_department_rounded,
                    color: AppColors.textDark, size: 18),
                SizedBox(width: 8),
                Text(
                  '7 Day Streak',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textDark,
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),

          // ── Headline ──
          const Text(
            'Your Health Tree is\nthriving!',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: AppColors.textDark,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Keep up your daily checkups to see it\nbloom.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
              height: 1.4,
            ),
          ),

          const SizedBox(height: 32),

          // ── Tree Illustration ──
          Container(
            height: 280,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF0F172A), // Dark night sky
                  Color(0xFF1E293B),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.2),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Center(
              // In a real app we'd load an image, here we customize a grown version
              // Just drawing a custom full grown painted plant
              child: CustomPaint(
                size: const Size(200, 200),
                painter: _FullGrownTreePainter(),
              ),
            ),
          ),

          const SizedBox(height: 32),

          // ── Growth Stage Card ──
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [
                BoxShadow(
                  color: AppColors.shadow,
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Growth Stage: Flowering',
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textDark,
                      ),
                    ),
                    Text(
                      '85%',
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // Progress Bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(50),
                  child: const LinearProgressIndicator(
                    value: 0.85,
                    minHeight: 10,
                    backgroundColor: AppColors.divider,
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                  ),
                ),
                const SizedBox(height: 16),
                RichText(
                  text: const TextSpan(
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted,
                      height: 1.5,
                    ),
                    children: [
                      TextSpan(
                          text:
                              "Your consistent morning vitals and medication checks have nourished your tree's health roots. Just "),
                      TextSpan(
                        text: '2 more days',
                        style: TextStyle(
                          color: AppColors.primaryDark,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      TextSpan(text: ' to reach Level 12!'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── Action Buttons ──
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppColors.primary, width: 2),
                  ),
                  child: const Column(
                    children: [
                      Icon(Icons.energy_savings_leaf_rounded,
                          color: AppColors.primary, size: 24),
                      SizedBox(height: 8),
                      Text(
                        'Collect XP',
                        style: TextStyle(
                          fontFamily: 'Nunito',
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textDark,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.4),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Column(
                    children: [
                      Icon(Icons.auto_awesome_rounded,
                          color: Colors.white, size: 24),
                      SizedBox(height: 8),
                      Text(
                        'Daily Task',
                        style: TextStyle(
                          fontFamily: 'Nunito',
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ── Static Full Grown Tree Painter ──
class _FullGrownTreePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height;

    // Draw full thick leaves arrangement
    _drawLeavesCluster(canvas, cx, cy - 30);
  }

  void _drawLeavesCluster(Canvas canvas, double cx, double cy) {
    final colors = [
      const Color(0xFF14532D), // Deepest green
      const Color(0xFF166534),
      const Color(0xFF15803D),
      const Color(0xFF16A34A),
      const Color(0xFF22C55E), // Lightest
    ];

    // Layers of leaves from back to front
    _drawRosette(canvas, cx, cy, 1.0, colors[0]);
    _drawRosette(canvas, cx, cy, 0.8, colors[1], offsetAngle: 0.5);
    _drawRosette(canvas, cx, cy, 0.6, colors[2]);
    _drawRosette(canvas, cx, cy, 0.45, colors[3], offsetAngle: 0.5);
    _drawRosette(canvas, cx, cy, 0.3, colors[4]);
  }

  void _drawRosette(Canvas canvas, double x, double y, double scale, Color color,
      {double offsetAngle = 0}) {
    const numLeaves = 8;
    for (int i = 0; i < numLeaves; i++) {
      final angle = (i * 2 * 3.14159 / numLeaves) + offsetAngle;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(angle);
      
      final leafPath = Path()
        ..moveTo(0, 0)
        ..cubicTo(-30 * scale, -40 * scale, -20 * scale, -100 * scale, 0, -110 * scale)
        ..cubicTo(20 * scale, -100 * scale, 30 * scale, -40 * scale, 0, 0)
        ..close();
      
      final paint = Paint()..color = color;
      canvas.drawPath(leafPath, paint);
      
      // Vein
      final veinPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawLine(const Offset(0, 0), Offset(0, -90 * scale), veinPaint);
      
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
