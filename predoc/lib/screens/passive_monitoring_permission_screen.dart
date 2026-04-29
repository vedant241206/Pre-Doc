// PassiveMonitoringPermissionScreen — Day 8
//
// Shown ONCE after basic_info, before the main home screen.
// Explains passive monitoring to the user and lets them choose
// which optional permissions to enable.
//
// Permissions handled here:
//   1. Usage Stats (special, opens system settings)
//   2. Activity Recognition (optional runtime permission)
//   3. Location (optional, for nearby doctor feature)
//
// After this screen, passiveMonitoringDone = true → user goes to /home.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import '../theme/app_theme.dart';
import '../utils/local_storage.dart';
import '../services/passive_monitoring_service.dart';
import '../widgets/predoc_button.dart';

class PassiveMonitoringPermissionScreen extends StatefulWidget {
  const PassiveMonitoringPermissionScreen({super.key});

  @override
  State<PassiveMonitoringPermissionScreen> createState() =>
      _PassiveMonitoringPermissionScreenState();
}

class _PassiveMonitoringPermissionScreenState
    extends State<PassiveMonitoringPermissionScreen>
    with TickerProviderStateMixin {

  // Permission states
  bool _usageStatsGranted          = false;
  bool _activityRecognitionGranted = false;
  bool _locationGranted            = false;

  // Loading states
  bool _checkingUsage    = false;
  bool _checkingActivity = false;
  bool _checkingLocation = false;

  late AnimationController _pulseController;
  late Animation<double>   _pulseScale;

  static const _passiveSvc = PassiveMonitoringService();

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _pulseScale = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Check current permission states
    _checkAllPermissions();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  // ── Permission Checks ──────────────────────────────────────────

  Future<void> _checkAllPermissions() async {
    await _checkUsageStats();
    await _checkActivityRecognition();
    await _checkLocation();
  }

  Future<void> _checkUsageStats() async {
    final granted = await _passiveSvc.isUsageStatsGranted();
    if (mounted) setState(() => _usageStatsGranted = granted);
    if (granted) await LocalStorage.setUsageStatsEnabled(true);
  }

  Future<void> _checkActivityRecognition() async {
    final status = await Permission.activityRecognition.status;
    if (mounted) {
      setState(() =>
          _activityRecognitionGranted = status.isGranted);
    }
  }

  Future<void> _checkLocation() async {
    final status = await Permission.location.status;
    if (mounted) {
      setState(() => _locationGranted = status.isGranted);
    }
  }

  // ── Permission Requests ────────────────────────────────────────

  Future<void> _requestUsageStats() async {
    setState(() => _checkingUsage = true);
    // Opens system Usage Access settings — user must toggle manually
    await _passiveSvc.openUsageSettings();
    // Wait briefly for user to return from settings
    await Future.delayed(const Duration(milliseconds: 800));
    await _checkUsageStats();
    if (mounted) setState(() => _checkingUsage = false);
  }

  Future<void> _requestActivityRecognition() async {
    setState(() => _checkingActivity = true);
    final status = await Permission.activityRecognition.request();
    if (mounted) {
      setState(() {
        _activityRecognitionGranted = status.isGranted;
        _checkingActivity = false;
      });
    }
  }

  Future<void> _requestLocation() async {
    setState(() => _checkingLocation = true);
    final status = await Permission.location.request();
    if (mounted) {
      setState(() {
        _locationGranted = status.isGranted;
        _checkingLocation = false;
      });
    }
  }

  // ── Continue ───────────────────────────────────────────────────

  Future<void> _onContinue() async {
    await LocalStorage.setPassiveMonitoringDone();
    if (mounted) context.go('/home');
  }

  Future<void> _onSkip() async {
    await LocalStorage.setPassiveMonitoringDone();
    if (mounted) context.go('/home');
  }

  // ── Build ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // ── Header ──────────────────────────────────────
              _buildHeader(),

              // ── Hero Section ─────────────────────────────────
              _buildHeroSection(),

              // ── Privacy Promise Card ──────────────────────────
              _buildPrivacyCard(),

              const SizedBox(height: 28),

              // ── Permission Items ──────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Permissions',
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Required and optional access for passive monitoring',
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 1. Usage Stats (required for screen time)
                    _PermissionCard(
                      icon: Icons.phone_android_rounded,
                      iconColor: AppColors.primary,
                      iconBg: AppColors.primaryLight,
                      title: 'Screen Time (Usage Stats)',
                      description:
                          'Tracks total daily screen time and night usage. '
                          'Required for screen health insights.\n\n'
                          '⚠️ Opens System Settings — enable "Usage Access" for Predoc.',
                      badge: 'REQUIRED',
                      badgeColor: const Color(0xFFEF4444),
                      isGranted: _usageStatsGranted,
                      isLoading: _checkingUsage,
                      requiresSettings: true,
                      onTap: _usageStatsGranted ? null : _requestUsageStats,
                    ),

                    const SizedBox(height: 12),

                    // 2. Activity Recognition (optional)
                    _PermissionCard(
                      icon: Icons.directions_walk_rounded,
                      iconColor: const Color(0xFF10B981),
                      iconBg: const Color(0xFFD1FAE5),
                      title: 'Activity Recognition',
                      description:
                          'Detects physical activity levels and step estimates. '
                          'Used to flag sedentary behaviour. Optional.',
                      badge: 'OPTIONAL',
                      badgeColor: const Color(0xFF6366F1),
                      isGranted: _activityRecognitionGranted,
                      isLoading: _checkingActivity,
                      requiresSettings: false,
                      onTap: _activityRecognitionGranted
                          ? null
                          : _requestActivityRecognition,
                    ),

                    const SizedBox(height: 12),

                    // 3. Location (optional)
                    _PermissionCard(
                      icon: Icons.location_on_rounded,
                      iconColor: const Color(0xFFF59E0B),
                      iconBg: const Color(0xFFFEF3C7),
                      title: 'Location Access',
                      description:
                          'Used only to find nearby doctors and clinics. '
                          'Never stored or shared. Optional.',
                      badge: 'OPTIONAL',
                      badgeColor: const Color(0xFF6366F1),
                      isGranted: _locationGranted,
                      isLoading: _checkingLocation,
                      requiresSettings: false,
                      onTap: _locationGranted ? null : _requestLocation,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // ── Buttons ────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    PredocButton(
                      label: 'Enable & Continue',
                      suffixIcon: Icons.arrow_forward_rounded,
                      onTap: _onContinue,
                      backgroundColor: AppColors.primary,
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: _onSkip,
                      child: const Text(
                        'Skip for now',
                        style: TextStyle(
                          fontFamily: 'Nunito',
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textMuted,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(50),
            ),
            child: const Text(
              'SETUP',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Hero Section ───────────────────────────────────────────────

  Widget _buildHeroSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
      child: Column(
        children: [
          // Animated icon
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) => Transform.scale(
              scale: _pulseScale.value,
              child: child,
            ),
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.20),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppColors.primary, AppColors.primaryDark],
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.monitor_heart_rounded,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                  // Accent dots
                  Positioned(
                    top: 10, right: 10,
                    child: Container(
                      width: 18, height: 18,
                      decoration: const BoxDecoration(
                        color: Color(0xFF10B981),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 14, left: 12,
                    child: Container(
                      width: 12, height: 12,
                      decoration: const BoxDecoration(
                        color: Color(0xFFF59E0B),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

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
                TextSpan(text: 'Passive '),
                TextSpan(
                  text: 'Health Monitoring',
                  style: TextStyle(color: AppColors.primary),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          const Text(
            'Predoc observes your daily patterns — screen time, '
            'activity and sleep — to give you deeper health insights.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  // ── Privacy Promise Card ────────────────────────────────────────

  Widget _buildPrivacyCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.primary.withValues(alpha: 0.08),
              AppColors.primaryLight,
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.18),
            width: 1.5,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.lock_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'YOUR PRIVACY IS PROTECTED',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                      letterSpacing: 1.1,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'We use your device usage and sensor data to generate '
                    'health insights. All data is processed locally and '
                    'never leaves your device.',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textDark,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// PERMISSION CARD WIDGET
// ─────────────────────────────────────────────────────────────

class _PermissionCard extends StatelessWidget {
  final IconData icon;
  final Color    iconColor;
  final Color    iconBg;
  final String   title;
  final String   description;
  final String   badge;
  final Color    badgeColor;
  final bool     isGranted;
  final bool     isLoading;
  final bool     requiresSettings;
  final VoidCallback? onTap;

  const _PermissionCard({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.description,
    required this.badge,
    required this.badgeColor,
    required this.isGranted,
    required this.isLoading,
    required this.requiresSettings,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isGranted
              ? const Color(0xFF22C55E).withValues(alpha: 0.4)
              : AppColors.divider,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: isGranted
                ? const Color(0xFF22C55E).withValues(alpha: 0.08)
                : AppColors.shadow,
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Icon
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isGranted
                      ? const Color(0xFFDCFCE7)
                      : iconBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isGranted ? Icons.check_circle_rounded : icon,
                  color: isGranted ? const Color(0xFF22C55E) : iconColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),

              // Title + badge
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: (isGranted
                                ? const Color(0xFF22C55E)
                                : badgeColor)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(50),
                      ),
                      child: Text(
                        isGranted ? 'GRANTED ✓' : badge,
                        style: TextStyle(
                          fontFamily: 'Nunito',
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: isGranted
                              ? const Color(0xFF22C55E)
                              : badgeColor,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Description
          Text(
            description,
            style: const TextStyle(
              fontFamily: 'Nunito',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
              height: 1.55,
            ),
          ),

          // Enable button (if not granted)
          if (!isGranted) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: onTap,
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Center(
                  child: isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (requiresSettings)
                              const Icon(Icons.settings_rounded,
                                  color: Colors.white, size: 16),
                            if (requiresSettings)
                              const SizedBox(width: 6),
                            Text(
                              requiresSettings
                                  ? 'Open Settings'
                                  : 'Enable',
                              style: const TextStyle(
                                fontFamily: 'Nunito',
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
