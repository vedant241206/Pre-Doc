import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/predoc_button.dart';

class MedCheckupScreen extends StatefulWidget {
  const MedCheckupScreen({super.key});

  @override
  State<MedCheckupScreen> createState() => _MedCheckupScreenState();
}

class _MedCheckupScreenState extends State<MedCheckupScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Header ──
          const Text(
            'Med Checkup',
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Position your face in the circle for scanning.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 40),

          // ── Scanner UI ──
          Stack(
            alignment: Alignment.center,
            children: [
              // Pulsing outer ring
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  return Container(
                    width: 200 + (_pulseController.value * 20),
                    height: 200 + (_pulseController.value * 20),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.primary.withValues(
                          alpha: 0.1 + (0.3 * (1 - _pulseController.value)),
                        ),
                        width: 2 + (_pulseController.value * 4),
                      ),
                    ),
                  );
                },
              ),
              // Inner solid circle with face icon
              Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.5),
                    width: 4,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.2),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.face_retouching_natural_rounded,
                  color: AppColors.primary,
                  size: 80,
                ),
              ),
              // Scanning line overlay
              Positioned(
                top: 20,
                child: AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    return Transform.translate(
                      offset: Offset(0, _pulseController.value * 140),
                      child: Container(
                        width: 140,
                        height: 2,
                        decoration: BoxDecoration(
                          color: AppColors.accentGreen,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.accentGreen.withValues(alpha: 0.8),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 32),

          // ── Speech Bubble ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(
                  color: AppColors.shadow,
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.smart_toy_rounded, color: AppColors.primary, size: 20),
                SizedBox(width: 10),
                Text(
                  'Scanning in progress...',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 40),

          // ── Live Feed Section ──
          Row(
            children: [
              const Text(
                'Live Diagnosis',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textDark,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.accentRed.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.circle, color: AppColors.accentRed, size: 8),
                    SizedBox(width: 4),
                    Text(
                      'LIVE FEED',
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: AppColors.accentRed,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          _diagnosisItem('Skin Texture', 'Smooth', Icons.water_drop_outlined),
          _diagnosisItem('Ocular Health', 'Healthy', Icons.visibility_outlined),
          _diagnosisItem('Hydration', 'Optimal', Icons.opacity_rounded),
          _diagnosisItem('Est. Pulse', '72 BPM', Icons.monitor_heart_outlined, isSpecial: true),

          const SizedBox(height: 40),

          // ── Finish Session ──
          PredocButton(
            label: 'Finish Session',
            onTap: () {},
          ),
        ],
      ),
    );
  }

  Widget _diagnosisItem(String label, String value, IconData icon, {bool isSpecial = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              color: AppColors.background,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 14),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Nunito',
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textDark,
            ),
          ),
          const Spacer(),
          if (isSpecial) ...[
            Container(
              height: 20,
              width: 40,
              margin: const EdgeInsets.only(right: 8),
              child: CustomPaint(painter: _MiniGraphPainter()),
            ),
          ],
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: isSpecial ? AppColors.primary : AppColors.accentGreen,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniGraphPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path()
      ..moveTo(0, size.height / 2)
      ..lineTo(size.width * 0.2, size.height / 2)
      ..lineTo(size.width * 0.4, size.height * 0.1)
      ..lineTo(size.width * 0.6, size.height * 0.9)
      ..lineTo(size.width * 0.8, size.height / 2)
      ..lineTo(size.width, size.height / 2);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
