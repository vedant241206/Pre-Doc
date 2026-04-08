import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';
import '../widgets/sapling_animation.dart';
import '../widgets/predoc_button.dart';
import '../utils/local_storage.dart';

class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key});

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen>
    with SingleTickerProviderStateMixin {
  bool _animationComplete = false;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeIn);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  void _onAnimationComplete() {
    setState(() => _animationComplete = true);
    _fadeController.forward();
  }

  Future<void> _onStartGrowing() async {
    await LocalStorage.setOnboardingDone();
    if (mounted) context.go('/auth');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const SizedBox(height: 36),

              // ── Logo Icon ──
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.18),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.health_and_safety_rounded,
                  size: 44,
                  color: AppColors.primary,
                ),
              ),

              const SizedBox(height: 20),

              // ── App Name ──
              const Text(
                'Predoc',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 42,
                  fontWeight: FontWeight.w900,
                  color: AppColors.primaryDark,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'DETECT EARLY, TREAT EARLY',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textLight,
                  letterSpacing: 2.0,
                ),
              ),

              const SizedBox(height: 32),

              // ── Sapling Animation ──
              Expanded(
                child: Center(
                  child: SaplingAnimation(
                    size: 260,
                    onComplete: _onAnimationComplete,
                  ),
                ),
              ),

              // ── Tagline pill ──
              AnimatedOpacity(
                opacity: _animationComplete ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 400),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(50),
                    boxShadow: const [
                      BoxShadow(
                        color: AppColors.shadow,
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.park_rounded,
                          color: AppColors.primary, size: 22),
                      SizedBox(width: 10),
                      Text(
                        'Your health journey begins today',
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
              ),

              const SizedBox(height: 28),

              // ── Progress dots ──
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _dot(active: true),
                  const SizedBox(width: 8),
                  _dot(active: false),
                  const SizedBox(width: 8),
                  _dot(active: false),
                ],
              ),

              const SizedBox(height: 24),

              // ── CTA Button ──
              FadeTransition(
                opacity: _fadeAnim,
                child: SlideTransition(
                  position: _slideAnim,
                  child: PredocButton(
                    label: 'Start Growing',
                    suffixIcon: Icons.arrow_forward_rounded,
                    onTap: _animationComplete ? _onStartGrowing : null,
                    backgroundColor: _animationComplete
                        ? AppColors.primary
                        : AppColors.primaryLight,
                    textColor: _animationComplete ? Colors.white : AppColors.primary,
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ── Terms ──
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: RichText(
                  textAlign: TextAlign.center,
                  text: const TextSpan(
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                    children: [
                      TextSpan(text: 'By continuing you agree to the '),
                      TextSpan(
                        text: 'Terms of Service',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dot({required bool active}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: active ? 28 : 10,
      height: 10,
      decoration: BoxDecoration(
        color: active ? AppColors.primary : AppColors.divider,
        borderRadius: BorderRadius.circular(5),
      ),
    );
  }
}
