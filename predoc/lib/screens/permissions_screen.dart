// PermissionsScreen — Day 13: Asks mic + camera + location ONCE only.
// Auto-skips if already granted. Uses new setPermissionsGranted() flag.

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
  bool _micGranted      = false;
  bool _cameraGranted   = false;
  bool _locationGranted = false;
  bool _isRequesting    = false;
  bool _agreeChecked    = false;

  bool get _allGranted => _micGranted && _cameraGranted && _locationGranted;

  late AnimationController _shieldController;
  late Animation<double>   _shieldScale;
  late Animation<double>   _shieldGlow;

  @override
  void initState() {
    super.initState();
    _shieldController = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat(reverse: true);
    _shieldScale = Tween<double>(begin: 1.0, end: 1.06).animate(
        CurvedAnimation(parent: _shieldController, curve: Curves.easeInOut));
    _shieldGlow  = Tween<double>(begin: 8.0, end: 22.0).animate(
        CurvedAnimation(parent: _shieldController, curve: Curves.easeInOut));

    // Check current permission status — auto-advance if all granted
    _checkExistingPermissions();
  }

  @override
  void dispose() { _shieldController.dispose(); super.dispose(); }

  // ── Check without requesting — determine current state ─────────────
  Future<void> _checkExistingPermissions() async {
    final mic  = await Permission.microphone.status;
    final cam  = await Permission.camera.status;
    final loc  = await Permission.location.status;

    if (!mounted) return;
    setState(() {
      _micGranted      = mic.isGranted;
      _cameraGranted   = cam.isGranted;
      _locationGranted = loc.isGranted;
    });

    // ALL already granted — auto-advance without showing dialog
    if (_micGranted && _cameraGranted && _locationGranted) {
      await LocalStorage.setPermissionsGranted();
      if (mounted) context.go('/basic_info');
    }
  }

  // ── Request all three permissions ─────────────────────────────────
  Future<void> _requestPermissions() async {
    setState(() => _isRequesting = true);

    final statuses = await [
      Permission.microphone,
      Permission.camera,
      Permission.location,
    ].request();

    final mic  = statuses[Permission.microphone]?.isGranted ?? false;
    final cam  = statuses[Permission.camera]?.isGranted     ?? false;
    final loc  = statuses[Permission.location]?.isGranted   ?? false;

    if (!mounted) return;
    setState(() {
      _micGranted      = mic;
      _cameraGranted   = cam;
      _locationGranted = loc;
      _isRequesting    = false;
    });

    if (!mic || !cam || !loc) {
      _showDeniedDialog(mic: mic, cam: cam, loc: loc);
    }
  }

  void _showDeniedDialog({required bool mic, required bool cam, required bool loc}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: AppColors.moderate, size: 26),
          SizedBox(width: 10),
          Text('Permissions Needed',
              style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w800,
                  fontSize: 17, color: AppColors.textDark)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _permRow('Microphone', mic),
              const SizedBox(height: 6),
              _permRow('Camera', cam),
              const SizedBox(height: 6),
              _permRow('Location', loc),
              const SizedBox(height: 14),
              const Text(
                'Predoc needs these to monitor your health.\nPlease allow them in Settings.',
                style: TextStyle(fontFamily: 'Nunito', fontSize: 13,
                    color: AppColors.textMuted, height: 1.5)),
            ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(fontFamily: 'Nunito', color: AppColors.textMuted,
                    fontWeight: FontWeight.w700))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(50))),
            onPressed: () { Navigator.pop(ctx); openAppSettings(); },
            child: const Text('Open Settings',
                style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w800))),
        ],
      ),
    );
  }

  Widget _permRow(String name, bool granted) => Row(children: [
    Icon(granted ? Icons.check_circle_rounded : Icons.cancel_rounded,
        color: granted ? AppColors.good : AppColors.risk, size: 20),
    const SizedBox(width: 8),
    Text(name, style: const TextStyle(fontFamily: 'Nunito', fontSize: 14,
        fontWeight: FontWeight.w600, color: AppColors.textDark)),
  ]);

  Future<void> _onContinue() async {
    if (!_allGranted || !_agreeChecked) return;
    await LocalStorage.setPermissionsGranted();
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
              _buildTopBar(),
              const SizedBox(height: 32),

              // ── Animated shield ──
              AnimatedBuilder(
                animation: _shieldController,
                builder: (_, child) => Transform.scale(
                  scale: _shieldScale.value,
                  child: Container(
                    width: 120, height: 120,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(32),
                      boxShadow: [BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.22),
                          blurRadius: _shieldGlow.value, spreadRadius: 2)],
                    ),
                    child: Stack(alignment: Alignment.center, children: [
                      Container(
                        width: 80, height: 80,
                        decoration: BoxDecoration(color: AppColors.primary,
                            borderRadius: BorderRadius.circular(22)),
                        child: const Icon(Icons.shield_rounded, color: Colors.white, size: 44)),
                      Positioned(top: 12, right: 12, child: Container(
                          width: 22, height: 22,
                          decoration: const BoxDecoration(
                              color: Color(0xFFB8860B), shape: BoxShape.circle))),
                      Positioned(bottom: 16, left: 14, child: Container(
                          width: 16, height: 16,
                          decoration: const BoxDecoration(
                              color: AppColors.primaryLight, shape: BoxShape.circle))),
                    ]),
                  ),
                ),
              ),

              const SizedBox(height: 28),

              // ── Headline ──
              RichText(
                textAlign: TextAlign.center,
                text: const TextSpan(
                  style: TextStyle(fontFamily: 'Nunito', fontSize: 26,
                      fontWeight: FontWeight.w900, color: AppColors.textDark),
                  children: [
                    TextSpan(text: 'Security & '),
                    TextSpan(text: 'Privacy First',
                        style: TextStyle(color: AppColors.primary)),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── Description card ──
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppColors.radiusCard),
                  boxShadow: const [BoxShadow(
                      color: AppColors.shadow, blurRadius: 12, offset: Offset(0, 4))],
                ),
                child: const Stack(children: [
                  Positioned(right: -6, top: -6,
                      child: Icon(Icons.lock_outline_rounded, size: 64,
                          color: AppColors.primaryLight)),
                  Text(
                    'Predoc needs Microphone, Camera and Location '
                    'to monitor your health. All data stays on your '
                    'device — nothing is uploaded.',
                    style: TextStyle(fontFamily: 'Nunito', fontSize: 15,
                        fontWeight: FontWeight.w600, color: AppColors.textDark, height: 1.6)),
                ]),
              ),

              const SizedBox(height: 24),

              // ── Per-permission status chips ──
              _permChip(Icons.mic_rounded,      'Microphone', _micGranted),
              const SizedBox(height: 10),
              _permChip(Icons.camera_alt_rounded,'Camera',    _cameraGranted),
              const SizedBox(height: 10),
              _permChip(Icons.location_on_rounded,'Location', _locationGranted),

              const SizedBox(height: 24),

              // ── Allow button ──
              _isRequesting
                  ? Container(
                      height: 58,
                      decoration: BoxDecoration(color: AppColors.primary,
                          borderRadius: BorderRadius.circular(50)),
                      child: const Center(child: SizedBox(width: 26, height: 26,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5))))
                  : PredocButton(
                      label: _allGranted
                          ? '✓  All Permissions Granted'
                          : 'Allow Permissions',
                      suffixIcon: _allGranted ? null : Icons.arrow_forward_rounded,
                      onTap: _allGranted ? null : _requestPermissions,
                      backgroundColor: _allGranted ? AppColors.good : AppColors.primary,
                    ),

              const SizedBox(height: 18),

              // ── Agree checkbox (enabled only when all granted) ──
              GestureDetector(
                onTap: _allGranted
                    ? () => setState(() => _agreeChecked = !_agreeChecked)
                    : null,
                child: Opacity(
                  opacity: _allGranted ? 1.0 : 0.45,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 26, height: 26,
                        decoration: BoxDecoration(
                          color: _agreeChecked ? AppColors.primary : AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.primary, width: 2)),
                        child: _agreeChecked
                            ? const Icon(Icons.check, size: 16, color: Colors.white)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      const Text('I agree — continue the app',
                          style: TextStyle(fontFamily: 'Nunito', fontSize: 15,
                              fontWeight: FontWeight.w700, color: AppColors.textDark)),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 28),

              // ── Info cards ──
              _infoCard(Icons.shield_rounded,        AppColors.primaryLight, AppColors.primary,
                  'LOCAL STORAGE', 'Your health records never leave this device.'),
              const SizedBox(height: 12),
              _infoCard(Icons.visibility_off_rounded, const Color(0xFFFEF3C7), const Color(0xFFB45309),
                  'ZERO TRACKING', 'No third-party cookies or data brokers.'),

              const SizedBox(height: 28),

              // ── Continue button ──
              AnimatedOpacity(
                opacity: (_allGranted && _agreeChecked) ? 1.0 : 0.35,
                duration: const Duration(milliseconds: 300),
                child: PredocButton(
                  label: 'Continue',
                  suffixIcon: Icons.arrow_forward_rounded,
                  onTap: _onContinue,
                  backgroundColor: AppColors.primaryDark,
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  // ── Permission chip ─────────────────────────────────────────────────
  Widget _permChip(IconData icon, String label, bool granted) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: granted ? const Color(0xFFF0FDF4) : Colors.white,
        borderRadius: BorderRadius.circular(AppColors.radiusCard),
        border: Border.all(
            color: granted ? AppColors.good : AppColors.divider, width: 1.5),
        boxShadow: const [BoxShadow(
            color: AppColors.shadow, blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
              color: granted ? const Color(0xFFDCFCE7) : AppColors.primaryLight,
              shape: BoxShape.circle),
          child: Icon(icon,
              color: granted ? AppColors.good : AppColors.primary, size: 22)),
        const SizedBox(width: 14),
        Expanded(child: Text(label,
            style: const TextStyle(fontFamily: 'Nunito', fontSize: 15,
                fontWeight: FontWeight.w800, color: AppColors.textDark))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
              color: granted
                  ? const Color(0xFFDCFCE7)
                  : const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(50)),
          child: Text(granted ? 'Granted ✓' : 'Required',
              style: TextStyle(fontFamily: 'Nunito', fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: granted ? AppColors.good : const Color(0xFFB45309)))),
      ]),
    );
  }

  Widget _buildTopBar() => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      const Row(children: [
        Icon(Icons.health_and_safety_rounded, color: AppColors.primary, size: 28),
        SizedBox(width: 8),
        Text('Predoc', style: TextStyle(fontFamily: 'Nunito', fontSize: 20,
            fontWeight: FontWeight.w800, color: AppColors.textDark)),
      ]),
      // Step indicator
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(50)),
        child: const Text('STEP 2 OF 4',
            style: TextStyle(fontFamily: 'Nunito', fontSize: 11,
                fontWeight: FontWeight.w800, color: AppColors.primary,
                letterSpacing: 1.2)),
      ),
    ],
  );

  Widget _infoCard(IconData icon, Color bg, Color ic, String title, String sub) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppColors.radiusCard),
          boxShadow: const [BoxShadow(
              color: AppColors.shadow, blurRadius: 10, offset: Offset(0, 3))],
        ),
        child: Row(children: [
          Container(width: 46, height: 46,
              decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
              child: Icon(icon, color: ic, size: 24)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontFamily: 'Nunito', fontSize: 12,
                fontWeight: FontWeight.w800, color: AppColors.primary, letterSpacing: 1.2)),
            const SizedBox(height: 2),
            Text(sub, style: const TextStyle(fontFamily: 'Nunito', fontSize: 13,
                fontWeight: FontWeight.w600, color: AppColors.textMuted)),
          ])),
        ]),
      );
}
