import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';
import '../widgets/predoc_button.dart';
import '../utils/local_storage.dart';
import '../services/firebase_service.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  bool _skipChecked = false;
  bool _isSigningIn = false;
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

  Future<void> _onGoogleSignIn() async {
    setState(() => _isSigningIn = true);
    
    try {
      final user = await FirebaseService.signInWithGoogle();
      
      if (mounted) setState(() => _isSigningIn = false);

      if (user != null) {
        if (mounted) _goNext();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Sign-In failed. Please try again.', style: TextStyle(fontFamily: 'Nunito')),
            backgroundColor: AppColors.risk,
          ));
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isSigningIn = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Auth Error: $e', style: const TextStyle(fontFamily: 'Nunito')),
          backgroundColor: AppColors.risk,
          duration: const Duration(seconds: 4),
        ));
      }
    }
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

                  // ── Clean Theme Icon ──
                  Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight.withValues(alpha: 0.3),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Container(
                        width: 110,
                        height: 110,
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.2),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.cloud_sync_rounded,
                          size: 52,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 36),

                  // ── Google Sign In ──
                  if (_isSigningIn)
                    const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: CircularProgressIndicator(color: AppColors.primary),
                    )
                  else
                    PredocButton(
                      label: 'CONTINUE WITH GOOGLE',
                      onTap: _onGoogleSignIn,
                      backgroundColor: Colors.white,
                      textColor: AppColors.textDark,
                      isOutlined: true,
                      prefixWidget: Image.network(
                        'https://cdn4.iconfinder.com/data/icons/logos-brands-7/512/google_logo-google_icongoogle-512.png',
                        width: 22,
                        height: 22,
                        errorBuilder: (context, error, stackTrace) => const Icon(Icons.g_mobiledata, size: 28, color: AppColors.primary),
                      ),
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

