// MonitoringPermissionScreen — Day 9 (Part 4)
//
// First screen shown to the user to explain the monitoring feature
// and request microphone permission. On "Allow & Start Monitoring",
// automatically starts ContinuousAudioService.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import '../theme/app_theme.dart';
import '../app_services.dart';
import '../services/storage_service.dart';
import '../utils/local_storage.dart';

class MonitoringPermissionScreen extends StatefulWidget {
  const MonitoringPermissionScreen({super.key});

  @override
  State<MonitoringPermissionScreen> createState() =>
      _MonitoringPermissionScreenState();
}

class _MonitoringPermissionScreenState
    extends State<MonitoringPermissionScreen>
    with SingleTickerProviderStateMixin {
  bool _loading = false;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _onAllow() async {
    if (_loading) return;
    setState(() => _loading = true);

    try {
      // Request microphone permission
      final status = await Permission.microphone.request();
      if (!status.isGranted) {
        if (mounted) {
          _showDeniedSnack();
          setState(() => _loading = false);
        }
        return;
      }

      // Load YAMNet if not yet loaded
      if (!appModelService.isLoaded) {
        await appModelService.loadModels();
      }

      // Auto-start ContinuousAudioService
      await appContinuousAudio.start();
      await StorageService.setLiveMonitoringEnabled(true);

      // Mark monitoring onboarding done
      await LocalStorage.setMonitoringOnboardingDone();

      if (mounted) context.go('/home');
    } catch (e) {
      debugPrint('[MonitoringPermission] Error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _onSkip() async {
    await LocalStorage.setMonitoringOnboardingDone();
    if (mounted) context.go('/home');
  }

  void _showDeniedSnack() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Microphone permission is required for health monitoring.',
          style: TextStyle(fontFamily: 'Nunito'),
        ),
        backgroundColor: Color(0xFFEF4444),
        duration: Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 48),

                    // ── Animated mic icon ───────────────────────────
                    AnimatedBuilder(
                      animation: _pulseAnim,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _pulseAnim.value,
                          child: child,
                        );
                      },
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              AppColors.primary,
                              AppColors.primaryDark,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.35),
                              blurRadius: 28,
                              spreadRadius: 6,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.mic_rounded,
                          color: Colors.white,
                          size: 56,
                        ),
                      ),
                    ),

                    const SizedBox(height: 36),

                    // ── Title ────────────────────────────────────────
                    const Text(
                      'Health Monitoring',
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

                    // ── Explanation ──────────────────────────────────
                    const Text(
                      'This app continuously monitors audio to detect early health signals like coughing, sneezing, and snoring.\n\nAll data stays on your device — nothing is uploaded or shared.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMuted,
                        height: 1.6,
                      ),
                    ),

                    const SizedBox(height: 36),

                    // ── Feature cards ────────────────────────────────
                    const _FeatureCard(
                      icon: Icons.lock_outline_rounded,
                      iconColor: Color(0xFF10B981),
                      title: 'Fully Private',
                      subtitle: 'No audio is ever recorded or stored. Only event counts.',
                    ),
                    const SizedBox(height: 12),
                    const _FeatureCard(
                      icon: Icons.notifications_active_outlined,
                      iconColor: Color(0xFF6366F1),
                      title: 'Transparent',
                      subtitle: 'A persistent notification is always shown when monitoring is active.',
                    ),
                    const SizedBox(height: 12),
                    const _FeatureCard(
                      icon: Icons.battery_saver_outlined,
                      iconColor: Color(0xFFF59E0B),
                      title: 'Battery Efficient',
                      subtitle: 'Inference runs every 2 seconds — minimal CPU and battery impact.',
                    ),
                    const SizedBox(height: 12),
                    const _FeatureCard(
                      icon: Icons.power_settings_new_rounded,
                      iconColor: Color(0xFFEF4444),
                      title: 'Stop Anytime',
                      subtitle: 'You can disable monitoring at any time from Settings.',
                    ),

                    const SizedBox(height: 48),
                  ],
                ),
              ),
            ),

            // ── Bottom buttons ────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 32),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        elevation: 4,
                        shadowColor: AppColors.primary.withValues(alpha: 0.4),
                      ),
                      onPressed: _loading ? null : _onAllow,
                      child: _loading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.mic_rounded, size: 22),
                                SizedBox(width: 10),
                                Text(
                                  'Allow & Start Monitoring',
                                  style: TextStyle(
                                    fontFamily: 'Nunito',
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextButton(
                    onPressed: _loading ? null : _onSkip,
                    child: const Text(
                      'Skip for now',
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textMuted,
                      ),
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

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;

  const _FeatureCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 22),
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
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                    height: 1.4,
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
