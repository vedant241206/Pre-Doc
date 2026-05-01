// IntroScreen — Day 13 UI Upgrade
// Layout: centered logo + "Predoc" + tagline at top
//         full-height sapling animation (seed → sprout → plant) in middle
//         "Get Started" CTA at bottom (appears after animation completes)
// NO scale/fade on main animation. Button: radius 16, primary purple, shadow.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';
import '../widgets/sapling_animation.dart';
import '../utils/local_storage.dart';

class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key});
  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen>
    with SingleTickerProviderStateMixin {

  bool _animationComplete = false;

  // Button slides up after animation finishes (slide-in only, no fade)
  late AnimationController _btnCtrl;
  late Animation<Offset>   _btnSlide;

  @override
  void initState() {
    super.initState();
    _btnCtrl  = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _btnSlide = Tween<Offset>(begin: const Offset(0, 1.4), end: Offset.zero)
        .animate(CurvedAnimation(parent: _btnCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() { _btnCtrl.dispose(); super.dispose(); }

  void _onSaplingComplete() {
    if (!mounted) return;
    setState(() => _animationComplete = true);
    _btnCtrl.forward();
  }

  Future<void> _onGetStarted() async {
    await LocalStorage.setSeenIntro();       // ← Day 13 flag
    if (mounted) context.go('/auth');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 40),

            // ── Logo + App Name ──────────────────────────────────────
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.18),
                    blurRadius: 22, offset: const Offset(0, 8))],
              ),
              child: const Icon(Icons.health_and_safety_rounded,
                  size: 42, color: AppColors.primary),
            ),

            const SizedBox(height: 16),

            const Text(
              'Predoc',
              style: TextStyle(
                fontFamily: 'Nunito', fontSize: 44,
                fontWeight: FontWeight.w900,
                color: AppColors.primaryDark,
                letterSpacing: -0.5,
              ),
            ),

            const SizedBox(height: 6),

            // ── Tagline ───────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
              decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(50)),
              child: const Text(
                'Detect early.  Treat early.',
                style: TextStyle(
                  fontFamily: 'Nunito', fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                  letterSpacing: 0.4,
                ),
              ),
            ),

            const SizedBox(height: 24),

            // ── Sapling Animation (seed → sprout → plant) ────────────
            Expanded(
              child: Center(
                child: SaplingAnimation(
                  size: 260,
                  onComplete: _onSaplingComplete,
                ),
              ),
            ),

            // ── Feature pills (appear after animation) ───────────────
            AnimatedOpacity(
              opacity: _animationComplete ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 400),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _featurePill(Icons.mic_rounded,          'Audio AI'),
                    const SizedBox(width: 8),
                    _featurePill(Icons.camera_alt_rounded,   'Vision'),
                    const SizedBox(width: 8),
                    _featurePill(Icons.lock_outline_rounded, 'Private'),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // ── Progress dots ──────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _dot(active: true),
                const SizedBox(width: 8),
                _dot(active: false),
                const SizedBox(width: 8),
                _dot(active: false),
                const SizedBox(width: 8),
                _dot(active: false),
              ],
            ),

            const SizedBox(height: 24),

            // ── CTA Button (slides up after animation) ────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: SlideTransition(
                position: _btnSlide,
                child: _GetStartedButton(
                  enabled: _animationComplete,
                  onTap: _onGetStarted,
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Terms ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: RichText(
                textAlign: TextAlign.center,
                text: const TextSpan(
                  style: TextStyle(fontFamily: 'Nunito', fontSize: 12,
                      color: AppColors.textMuted),
                  children: [
                    TextSpan(text: 'By continuing you agree to the '),
                    TextSpan(text: 'Terms of Service',
                        style: TextStyle(color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                            decoration: TextDecoration.underline)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _featurePill(IconData icon, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(50),
        boxShadow: const [BoxShadow(
            color: AppColors.shadow, blurRadius: 6, offset: Offset(0, 2))]),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: AppColors.primary),
      const SizedBox(width: 5),
      Text(label, style: const TextStyle(fontFamily: 'Nunito', fontSize: 12,
          fontWeight: FontWeight.w800, color: AppColors.textDark)),
    ]),
  );

  Widget _dot({required bool active}) => AnimatedContainer(
    duration: const Duration(milliseconds: 300),
    width: active ? 28 : 8, height: 8,
    decoration: BoxDecoration(
        color: active ? AppColors.primary : AppColors.divider,
        borderRadius: BorderRadius.circular(4)),
  );
}

// ── Get Started Button ─────────────────────────────────────────────────────

class _GetStartedButton extends StatefulWidget {
  final bool enabled;
  final VoidCallback onTap;
  const _GetStartedButton({required this.enabled, required this.onTap});

  @override
  State<_GetStartedButton> createState() => _GetStartedButtonState();
}

class _GetStartedButtonState extends State<_GetStartedButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressCtrl;
  late Animation<double>   _scale;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 120));
    _scale = Tween<double>(begin: 1.0, end: 0.97)
        .animate(CurvedAnimation(parent: _pressCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _pressCtrl.dispose(); super.dispose(); }

  Future<void> _handleTap() async {
    if (!widget.enabled) return;
    await _pressCtrl.forward();
    await _pressCtrl.reverse();
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      child: AnimatedBuilder(
        animation: _scale,
        builder: (_, child) => Transform.scale(scale: _scale.value, child: child),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            // Day 13 spec: radius 16, primary purple, soft shadow
            color: widget.enabled ? AppColors.primary : AppColors.primaryLight,
            borderRadius: BorderRadius.circular(AppColors.radiusCard),
            boxShadow: widget.enabled
                ? [BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.30),
                    blurRadius: 16, offset: const Offset(0, 6))]
                : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                widget.enabled ? 'Get Started' : 'Growing your tree…',
                style: TextStyle(
                  fontFamily: 'Nunito', fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: widget.enabled ? Colors.white : AppColors.primary,
                ),
              ),
              if (widget.enabled) ...[
                const SizedBox(width: 10),
                const Icon(Icons.arrow_forward_rounded,
                    color: Colors.white, size: 22),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
