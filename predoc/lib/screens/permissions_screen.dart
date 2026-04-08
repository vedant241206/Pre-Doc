import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import '../theme/app_theme.dart';
import '../widgets/predoc_button.dart';
import '../utils/local_storage.dart';

class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen>
    with SingleTickerProviderStateMixin {
  bool _permissionsGranted = false;
  bool _agreeChecked = false;
  bool _isRequesting = false;

  late AnimationController _shieldController;
  late Animation<double> _shieldScale;
  late Animation<double> _shieldGlow;

  @override
  void initState() {
    super.initState();
    _shieldController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _shieldScale = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _shieldController, curve: Curves.easeInOut),
    );
    _shieldGlow = Tween<double>(begin: 8.0, end: 22.0).animate(
      CurvedAnimation(parent: _shieldController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _shieldController.dispose();
    super.dispose();
  }

  Future<void> _requestPermissions() async {
    setState(() => _isRequesting = true);

    final statuses = await [
      Permission.camera,
      Permission.microphone,
    ].request();

    final cameraGranted = statuses[Permission.camera]?.isGranted ?? false;
    final micGranted = statuses[Permission.microphone]?.isGranted ?? false;

    setState(() {
      _permissionsGranted = cameraGranted && micGranted;
      _isRequesting = false;
    });

    if (!_permissionsGranted && mounted) {
      _showPermissionDeniedDialog(
        cameraGranted: cameraGranted,
        micGranted: micGranted,
      );
    }
  }

  void _showPermissionDeniedDialog({
    required bool cameraGranted,
    required bool micGranted,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: AppColors.backgroundCard,
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                color: AppColors.accent, size: 28),
            SizedBox(width: 10),
            Text(
              'Permissions Needed',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontWeight: FontWeight.w800,
                color: AppColors.textDark,
                fontSize: 18,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _permRow('Camera', cameraGranted),
            const SizedBox(height: 8),
            _permRow('Microphone', micGranted),
            const SizedBox(height: 16),
            const Text(
              'Please allow permissions in Settings to continue.',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 13,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(
                fontFamily: 'Nunito',
                color: AppColors.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(50)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            child: const Text(
              'Open Settings',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _permRow(String name, bool granted) {
    return Row(
      children: [
        Icon(
          granted ? Icons.check_circle_rounded : Icons.cancel_rounded,
          color: granted ? AppColors.accentGreen : AppColors.accentRed,
          size: 20,
        ),
        const SizedBox(width: 8),
        Text(
          name,
          style: const TextStyle(
            fontFamily: 'Nunito',
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textDark,
          ),
        ),
      ],
    );
  }

  Future<void> _onContinue() async {
    if (!_permissionsGranted || !_agreeChecked) return;
    await LocalStorage.setPermissionsDone();
    if (mounted) context.go('/basic_info');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 16),

              // ── Top bar ──
              _PermTopBar(),

              const SizedBox(height: 32),

              // ── Animated Shield Icon ──
              AnimatedBuilder(
                animation: _shieldController,
                builder: (context, child) => Transform.scale(
                  scale: _shieldScale.value,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(32),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.22),
                          blurRadius: _shieldGlow.value,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: const Icon(
                            Icons.shield_rounded,
                            color: Colors.white,
                            size: 44,
                          ),
                        ),
                        // Gold dot accent
                        Positioned(
                          top: 12,
                          right: 12,
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: const BoxDecoration(
                              color: Color(0xFFB8860B),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        // Light purple glow dot
                        Positioned(
                          bottom: 16,
                          left: 14,
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: const BoxDecoration(
                              color: AppColors.primaryLight,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 28),

              // ── Headline ──
              RichText(
                textAlign: TextAlign.center,
                text: const TextSpan(
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textDark,
                  ),
                  children: [
                    TextSpan(text: 'Security & '),
                    TextSpan(
                      text: 'Privacy First',
                      style: TextStyle(color: AppColors.primary),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── Description card ──
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(
                      color: AppColors.shadow,
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: const Stack(
                  children: [
                    // Background lock icon
                    Positioned(
                      right: -6,
                      top: -6,
                      child: Icon(
                        Icons.lock_outline_rounded,
                        size: 64,
                        color: AppColors.primaryLight,
                      ),
                    ),
                    Text(
                      'To use Predoc, you must allow required permissions. '
                      'We store only the required data in your local storage '
                      'only, so there are no privacy risks involved.',
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textDark,
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // ── Allow Button ──
              _isRequesting
                  ? Container(
                      height: 58,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(50),
                      ),
                      child: const Center(
                        child: SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        ),
                      ),
                    )
                  : PredocButton(
                      label: _permissionsGranted
                          ? '✓ Permissions Granted'
                          : 'I Allow Permissions',
                      suffixIcon: _permissionsGranted
                          ? null
                          : Icons.arrow_forward_rounded,
                      onTap: _permissionsGranted ? null : _requestPermissions,
                      backgroundColor: _permissionsGranted
                          ? AppColors.accentGreen
                          : AppColors.primary,
                    ),

              const SizedBox(height: 18),

              // ── Agree checkbox ──
              GestureDetector(
                onTap: _permissionsGranted
                    ? () => setState(() => _agreeChecked = !_agreeChecked)
                    : null,
                child: Opacity(
                  opacity: _permissionsGranted ? 1.0 : 0.45,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: _agreeChecked
                              ? AppColors.primary
                              : AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: AppColors.primary,
                            width: 2,
                          ),
                        ),
                        child: _agreeChecked
                            ? const Icon(Icons.check,
                                size: 16, color: Colors.white)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Continue the app',
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

              const SizedBox(height: 32),

              // ── Info cards ──
              const _InfoCard(
                icon: Icons.shield_rounded,
                iconBg: AppColors.primaryLight,
                iconColor: AppColors.primary,
                title: 'LOCAL STORAGE',
                subtitle: 'Your health records never leave this device.',
              ),

              const SizedBox(height: 14),

              const _InfoCard(
                icon: Icons.visibility_off_rounded,
                iconBg: Color(0xFFFEF3C7),
                iconColor: Color(0xFFB45309),
                title: 'ZERO TRACKING',
                subtitle: 'No third-party cookies or data brokers.',
              ),

              const SizedBox(height: 28),

              // ── Continue Button ──
              AnimatedOpacity(
                opacity: (_permissionsGranted && _agreeChecked) ? 1.0 : 0.4,
                duration: const Duration(milliseconds: 300),
                child: PredocButton(
                  label: 'Continue',
                  suffixIcon: Icons.arrow_forward_rounded,
                  onTap: _onContinue,
                  backgroundColor: AppColors.primaryDark,
                ),
              ),

              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermTopBar extends StatelessWidget {
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
          ),
          child: const Icon(Icons.person_rounded,
              color: AppColors.primary, size: 24),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;

  const _InfoCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: iconBg,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
