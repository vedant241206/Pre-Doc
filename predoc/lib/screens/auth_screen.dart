import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';
import '../widgets/predoc_button.dart';
import '../utils/local_storage.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  bool _skipChecked = false;
  late AnimationController _entryController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _fadeAnim =
        CurvedAnimation(parent: _entryController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entryController, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _entryController.dispose();
    super.dispose();
  }

  void _goNext() => context.go('/permissions');

  Future<void> _onCreateAccount() async {
    await LocalStorage.setLoggedIn();
    if (mounted) _goNext();
  }

  Future<void> _onSignIn() async {
    await LocalStorage.setLoggedIn();
    if (mounted) _goNext();
  }

  Future<void> _onSkip() async {
    if (!_skipChecked) return;
    await LocalStorage.setSkipAuth(true);
    await LocalStorage.setLoggedIn();
    if (mounted) _goNext();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(
            position: _slideAnim,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 16),

                  // ── Top bar ──
                  _TopBar(),

                  const SizedBox(height: 36),

                  // ── Security First pill ──
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: const Text(
                      'SECURITY FIRST',
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textMid,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── Headline ──
                  const Text(
                    'We recommend to login\nto save your progress',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textDark,
                      height: 1.3,
                    ),
                  ),

                  const SizedBox(height: 28),

                  // ── Character illustration ──
                  _CharacterIllustration(),

                  const SizedBox(height: 36),

                  // ── Create Account ──
                  PredocButton(
                    label: 'CREATE ACCOUNT',
                    onTap: _onCreateAccount,
                  ),

                  const SizedBox(height: 14),

                  // ── Sign In ──
                  PredocButton(
                    label: 'I ALREADY HAVE AN ACCOUNT',
                    onTap: _onSignIn,
                    isOutlined: true,
                    backgroundColor: Colors.white,
                    textColor: AppColors.textDark,
                  ),

                  const SizedBox(height: 28),

                  // ── Skip checkbox ──
                  GestureDetector(
                    onTap: () =>
                        setState(() => _skipChecked = !_skipChecked),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 16),
                      decoration: BoxDecoration(
                        color: _skipChecked
                            ? AppColors.primaryLight
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _skipChecked
                              ? AppColors.primary
                              : AppColors.divider,
                          width: 1.5,
                          style: BorderStyle.solid,
                        ),
                      ),
                      child: Row(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: _skipChecked
                                  ? AppColors.primary
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(
                                color: AppColors.primary,
                                width: 2,
                              ),
                            ),
                            child: _skipChecked
                                ? const Icon(Icons.check,
                                    size: 14, color: Colors.white)
                                : null,
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              "I don't want to sign in, I am ok if my progress is lost",
                              style: TextStyle(
                                fontFamily: 'Nunito',
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textDark,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── Skip CTA (shows when checked) ──
                  AnimatedCrossFade(
                    duration: const Duration(milliseconds: 300),
                    firstCurve: Curves.easeOut,
                    secondCurve: Curves.easeIn,
                    crossFadeState: _skipChecked
                        ? CrossFadeState.showFirst
                        : CrossFadeState.showSecond,
                    firstChild: Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: PredocButton(
                        label: 'Continue Without Account',
                        suffixIcon: Icons.arrow_forward_rounded,
                        onTap: _onSkip,
                        backgroundColor: AppColors.accentGreen,
                      ),
                    ),
                    secondChild: const SizedBox.shrink(),
                  ),

                  const SizedBox(height: 28),

                  // ── Terms ──
                  RichText(
                    textAlign: TextAlign.center,
                    text: const TextSpan(
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 11,
                        color: AppColors.textMuted,
                        letterSpacing: 0.5,
                      ),
                      children: [
                        TextSpan(
                            text: 'BY CONTINUING YOU AGREE TO OUR '),
                        TextSpan(
                          text: 'TERMS',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w800,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                        TextSpan(text: ' & '),
                        TextSpan(
                          text: 'PRIVACY POLICY',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w800,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Top bar with logo and avatar ──
class _TopBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Row(
          children: [
            Icon(Icons.health_and_safety_rounded,
                color: AppColors.primary, size: 28),
            SizedBox(width: 8),
            Text(
              'Predoc',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.textDark,
              ),
            ),
          ],
        ),
        Container(
          width: 42,
          height: 42,
          decoration: const BoxDecoration(
            color: AppColors.primaryLight,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.shadow,
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: const Icon(Icons.person_rounded,
              color: AppColors.primary, size: 24),
        ),
      ],
    );
  }
}

// ── Cartoon character illustration ──
class _CharacterIllustration extends StatefulWidget {
  @override
  State<_CharacterIllustration> createState() => _CharacterIllustrationState();
}

class _CharacterIllustrationState extends State<_CharacterIllustration>
    with SingleTickerProviderStateMixin {
  late AnimationController _bounce;
  late Animation<double> _bounceAnim;

  @override
  void initState() {
    super.initState();
    _bounce = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _bounceAnim = Tween<double>(begin: 0, end: -8).animate(
      CurvedAnimation(parent: _bounce, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _bounce.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _bounceAnim,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, _bounceAnim.value),
        child: child,
      ),
      child: Container(
        width: 200,
        height: 200,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF1B4F72),
              Color(0xFF2E86AB),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.2),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: CustomPaint(painter: _CharacterPainter()),
      ),
    );
  }
}

class _CharacterPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Body/shirt (light blue)
    final bodyPaint = Paint()..color = const Color(0xFF5DADE2);
    final bodyPath = Path()
      ..moveTo(cx - 45, cy + 30)
      ..quadraticBezierTo(cx - 50, cy + 80, cx - 30, cy + 100)
      ..lineTo(cx + 30, cy + 100)
      ..quadraticBezierTo(cx + 50, cy + 80, cx + 45, cy + 30)
      ..close();
    canvas.drawPath(bodyPath, bodyPaint);

    // Neck
    final neckPaint = Paint()..color = const Color(0xFFF5CBA7);
    canvas.drawRect(
      Rect.fromCenter(center: Offset(cx, cy + 16), width: 28, height: 22),
      neckPaint,
    );

    // Head
    final headPaint = Paint()..color = const Color(0xFFF5CBA7);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy - 22), width: 80, height: 88),
      headPaint,
    );

    // Hair (brown)
    final hairPaint = Paint()..color = const Color(0xFF6E3B1A);
    final hairPath = Path()
      ..moveTo(cx - 40, cy - 30)
      ..quadraticBezierTo(cx - 42, cy - 72, cx, cy - 78)
      ..quadraticBezierTo(cx + 42, cy - 72, cx + 40, cy - 30)
      ..quadraticBezierTo(cx + 44, cy - 55, cx + 38, cy - 38)
      ..quadraticBezierTo(cx, cy - 85, cx - 38, cy - 38)
      ..quadraticBezierTo(cx - 44, cy - 55, cx - 40, cy - 30)
      ..close();
    canvas.drawPath(hairPath, hairPaint);

    // Left eye
    final eyeWhitePaint = Paint()..color = Colors.white;
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx - 18, cy - 20), width: 22, height: 26),
      eyeWhitePaint,
    );
    // Right eye
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx + 18, cy - 20), width: 22, height: 26),
      eyeWhitePaint,
    );

    // Pupils (blue-grey)
    final pupilPaint = Paint()..color = const Color(0xFF2E86AB);
    canvas.drawCircle(Offset(cx - 18, cy - 20), 7, pupilPaint);
    canvas.drawCircle(Offset(cx + 18, cy - 20), 7, pupilPaint);

    // Pupil shine
    final shinePaint = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(cx - 15, cy - 23), 2.5, shinePaint);
    canvas.drawCircle(Offset(cx + 21, cy - 23), 2.5, shinePaint);

    // Smile
    final smilePaint = Paint()
      ..color = const Color(0xFFE74C3C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final smilePath = Path()
      ..moveTo(cx - 16, cy - 2)
      ..quadraticBezierTo(cx, cy + 12, cx + 16, cy - 2);
    canvas.drawPath(smilePath, smilePaint);

    // Cheek blush
    final blushPaint = Paint()..color = const Color(0xFFFF8C94).withValues(alpha: 0.4);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx - 30, cy - 8), width: 20, height: 10),
      blushPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx + 30, cy - 8), width: 20, height: 10),
      blushPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
