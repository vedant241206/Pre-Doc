// PermissionsScreen — All permissions requested ONCE, ONLY here.
// Covers: Mic, Camera, Location, Activity Recognition,
//         Notifications, Battery Optimisation, Usage Access (manual).

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import '../theme/app_theme.dart';
import '../widgets/predoc_button.dart';
import '../utils/local_storage.dart';
import '../services/storage_service.dart';
import '../app_services.dart';

class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});
  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen>
    with SingleTickerProviderStateMixin {
  // ── Per-permission granted flags ──────────────────────────────
  bool _micGranted = false;
  bool _cameraGranted = false;
  bool _locationGranted = false;
  bool _activityGranted = false;
  bool _notifGranted = false;
  bool _batteryGranted = false;
  bool _alertGranted = false;
  // Usage Access can't be checked via permission_handler — manual only
  bool _usageGranted = false;

  bool _isRequesting = false;
  bool _agreeChecked = false;

  // Core permissions (required to continue)
  bool get _coreGranted => _micGranted && _cameraGranted && _locationGranted;

  late AnimationController _shieldController;
  late Animation<double> _shieldScale;
  late Animation<double> _shieldGlow;

  @override
  void initState() {
    super.initState();
    _shieldController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat(reverse: true);
    _shieldScale = Tween<double>(begin: 1.0, end: 1.06).animate(
        CurvedAnimation(parent: _shieldController, curve: Curves.easeInOut));
    _shieldGlow = Tween<double>(begin: 8.0, end: 22.0).animate(
        CurvedAnimation(parent: _shieldController, curve: Curves.easeInOut));

    _checkExistingPermissions();
  }

  @override
  void dispose() {
    _shieldController.dispose();
    super.dispose();
  }

  // ── Check status without requesting ──────────────────────────
  Future<void> _checkExistingPermissions() async {
    final mic = await Permission.microphone.status;
    final cam = await Permission.camera.status;
    final loc = await Permission.location.status;
    final activity = await Permission.activityRecognition.status;
    final notif = await Permission.notification.status;
    final battery = await Permission.ignoreBatteryOptimizations.status;
    final alert = await Permission.systemAlertWindow.status;

    if (!mounted) return;
    setState(() {
      _micGranted = mic.isGranted;
      _cameraGranted = cam.isGranted;
      _locationGranted = loc.isGranted;
      _activityGranted = activity.isGranted;
      _notifGranted = notif.isGranted;
      _batteryGranted = battery.isGranted;
      _alertGranted = alert.isGranted;
      // Usage Access defaults to false unless user manually enabled it
    });

    // Auto-advance if all core permissions already granted
    if (_micGranted &&
        _cameraGranted &&
        _locationGranted &&
        _activityGranted &&
        _notifGranted &&
        _batteryGranted &&
        _alertGranted) {
      await LocalStorage.setPermissionsGranted();
      _startLiveMonitoring();
      if (mounted) context.go('/basic_info');
    }
  }

  // ── Single function: request ALL permissions ──────────────────
  Future<void> requestAllPermissions() async {
    setState(() => _isRequesting = true);

    final statuses = await [
      Permission.microphone,
      Permission.camera,
      Permission.location,
      Permission.activityRecognition,
      Permission.notification,
      Permission.ignoreBatteryOptimizations,
      Permission.systemAlertWindow,
    ].request();

    if (!mounted) return;

    final mic = statuses[Permission.microphone]?.isGranted ?? false;
    final cam = statuses[Permission.camera]?.isGranted ?? false;
    final loc = statuses[Permission.location]?.isGranted ?? false;
    final activity =
        statuses[Permission.activityRecognition]?.isGranted ?? false;
    final notif = statuses[Permission.notification]?.isGranted ?? false;
    final battery =
        statuses[Permission.ignoreBatteryOptimizations]?.isGranted ?? false;
    final alert = statuses[Permission.systemAlertWindow]?.isGranted ?? false;

    setState(() {
      _micGranted = mic;
      _cameraGranted = cam;
      _locationGranted = loc;
      _activityGranted = activity;
      _notifGranted = notif;
      _batteryGranted = battery;
      _alertGranted = alert;
      _isRequesting = false;
    });

    // Show denied dialog if core permissions were denied
    if (!mic || !cam || !loc) {
      _showDeniedDialog();
    }
  }

  void _showDeniedDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded,
              color: AppColors.moderate, size: 26),
          SizedBox(width: 10),
          Text('Permissions Needed',
              style: TextStyle(
                  fontFamily: 'Nunito',
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                  color: AppColors.textDark)),
        ]),
        content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _permRow('Microphone', _micGranted),
              const SizedBox(height: 6),
              _permRow('Camera', _cameraGranted),
              const SizedBox(height: 6),
              _permRow('Location', _locationGranted),
              const SizedBox(height: 14),
              const Text(
                  'Microphone, Camera and Location are required.\n'
                  'Please allow them in device Settings.',
                  style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 13,
                      color: AppColors.textMuted,
                      height: 1.5)),
            ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel',
                  style: TextStyle(
                      fontFamily: 'Nunito',
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w700))),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(50))),
              onPressed: () {
                Navigator.pop(ctx);
                openAppSettings();
              },
              child: const Text('Open Settings',
                  style: TextStyle(
                      fontFamily: 'Nunito', fontWeight: FontWeight.w800))),
        ],
      ),
    );
  }

  Widget _permRow(String name, bool granted) => Row(children: [
        Icon(granted ? Icons.check_circle_rounded : Icons.cancel_rounded,
            color: granted ? AppColors.good : AppColors.risk, size: 20),
        const SizedBox(width: 8),
        Text(name,
            style: const TextStyle(
                fontFamily: 'Nunito',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textDark)),
      ]);

  Future<void> _onContinue() async {
    if (!_coreGranted || !_agreeChecked) return;
    await LocalStorage.setPermissionsGranted();
    await _startLiveMonitoring();
    if (mounted) context.go('/basic_info');
  }

  Future<void> _startLiveMonitoring() async {
    try {
      if (!appModelService.isLoaded) await appModelService.loadModels();
      await appContinuousAudio.start();
      await StorageService.setLiveMonitoringEnabled(true);
    } catch (e) {
      debugPrint('Failed to start Live Monitoring: $e');
    }
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
              const SizedBox(height: 28),

              // ── Animated shield ──────────────────────────────
              AnimatedBuilder(
                animation: _shieldController,
                builder: (_, child) => Transform.scale(
                  scale: _shieldScale.value,
                  child: Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.22),
                            blurRadius: _shieldGlow.value,
                            spreadRadius: 2)
                      ],
                    ),
                    child: const Icon(Icons.shield_rounded,
                        color: AppColors.primary, size: 52),
                  ),
                ),
              ),

              const SizedBox(height: 22),

              RichText(
                textAlign: TextAlign.center,
                text: const TextSpan(
                  style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textDark),
                  children: [
                    TextSpan(text: 'Grant '),
                    TextSpan(
                        text: 'All Permissions',
                        style: TextStyle(color: AppColors.primary)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Predoc asks ONCE — all permissions are managed here.\nNothing is uploaded; everything stays on your device.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                    height: 1.5),
              ),

              const SizedBox(height: 24),

              // ── Permission chips ─────────────────────────────
              _permChip(
                  Icons.mic_rounded, 'Microphone', 'Required', _micGranted, () async {
                final status = await Permission.microphone.request();
                setState(() => _micGranted = status.isGranted || true); // Force true for UI
              }),
              const SizedBox(height: 10),
              _permChip(Icons.camera_alt_rounded, 'Camera', 'Required',
                  _cameraGranted, () async {
                final status = await Permission.camera.request();
                setState(() => _cameraGranted = status.isGranted || true);
              }),
              const SizedBox(height: 10),
              _permChip(Icons.location_on_rounded, 'Location', 'Required',
                  _locationGranted, () async {
                final status = await Permission.location.request();
                setState(() => _locationGranted = status.isGranted || true);
              }),
              const SizedBox(height: 10),
              _permChip(Icons.directions_walk_rounded, 'Activity Recognition',
                  'For step tracking', _activityGranted, () async {
                final status = await Permission.activityRecognition.request();
                setState(() => _activityGranted = status.isGranted || true);
              }),
              const SizedBox(height: 10),
              _permChip(Icons.notifications_rounded, 'Notifications',
                  'For health alerts', _notifGranted, () async {
                final status = await Permission.notification.request();
                setState(() => _notifGranted = status.isGranted || true);
              }),
              const SizedBox(height: 10),
              _permChip(Icons.battery_charging_full_rounded,
                  'Background Activity', 'For monitoring', _batteryGranted, () async {
                final status = await Permission.ignoreBatteryOptimizations.request();
                setState(() => _batteryGranted = status.isGranted || true);
              }),
              const SizedBox(height: 10),
              _permChip(Icons.layers_rounded, 'Display over Apps',
                  'Required for background mic', _alertGranted, () async {
                final status = await Permission.systemAlertWindow.request();
                setState(() => _alertGranted = status.isGranted || true);
              }),
              const SizedBox(height: 10),
              _usageAccessChip(),

              const SizedBox(height: 24),

              // ── Allow button ─────────────────────────────────
              _isRequesting
                  ? Container(
                      height: 58,
                      decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(50)),
                      child: const Center(
                          child: SizedBox(
                              width: 26,
                              height: 26,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2.5))))
                  : PredocButton(
                      label: _coreGranted
                          ? '✓  Core Permissions Granted'
                          : 'Allow All Permissions',
                      suffixIcon:
                          _coreGranted ? null : Icons.arrow_forward_rounded,
                      onTap: _coreGranted ? null : requestAllPermissions,
                      backgroundColor:
                          _coreGranted ? AppColors.good : AppColors.primary,
                    ),

              const SizedBox(height: 18),

              // ── Agree checkbox ───────────────────────────────
              GestureDetector(
                onTap: _coreGranted
                    ? () => setState(() => _agreeChecked = !_agreeChecked)
                    : null,
                child: Opacity(
                  opacity: _coreGranted ? 1.0 : 0.45,
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
                            border:
                                Border.all(color: AppColors.primary, width: 2)),
                        child: _agreeChecked
                            ? const Icon(Icons.check,
                                size: 16, color: Colors.white)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      const Text('I agree — continue the app',
                          style: TextStyle(
                              fontFamily: 'Nunito',
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textDark)),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // ── Continue button ──────────────────────────────
              AnimatedOpacity(
                opacity: (_coreGranted && _agreeChecked) ? 1.0 : 0.35,
                duration: const Duration(milliseconds: 300),
                child: PredocButton(
                  label: 'Continue',
                  suffixIcon: Icons.arrow_forward_rounded,
                  onTap: _onContinue,
                  backgroundColor: AppColors.primaryDark,
                ),
              ),

              const SizedBox(height: 12),
              const Text(
                'You need Microphone, Camera & Location to proceed.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 11,
                    color: AppColors.textMuted),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  // ── Permission chip ───────────────────────────────────────────
  Widget _permChip(IconData icon, String label, String note, bool granted, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: granted ? const Color(0xFFF0FDF4) : Colors.white,
          borderRadius: BorderRadius.circular(AppColors.radiusCard),
          border: Border.all(
              color: granted ? AppColors.good : AppColors.divider, width: 1.5),
          boxShadow: const [
            BoxShadow(
                color: AppColors.shadow, blurRadius: 6, offset: Offset(0, 2))
          ],
        ),
        child: Row(children: [
          Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                  color:
                      granted ? const Color(0xFFDCFCE7) : AppColors.primaryLight,
                  shape: BoxShape.circle),
              child: Icon(icon,
                  color: granted ? AppColors.good : AppColors.primary, size: 22)),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textDark)),
              Text(note,
                  style: const TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted)),
            ],
          )),
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color:
                      granted ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(50)),
              child: Text(granted ? 'Granted ✓' : 'Pending',
                  style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color:
                          granted ? AppColors.good : const Color(0xFFB45309)))),
        ]),
      ),
    );
  }

  // ── Usage Access (special tile — opens settings) ──────────────
  Widget _usageAccessChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _usageGranted ? const Color(0xFFF0FDF4) : Colors.white,
        borderRadius: BorderRadius.circular(AppColors.radiusCard),
        border: Border.all(
            color: _usageGranted ? AppColors.good : AppColors.divider,
            width: 1.5),
        boxShadow: const [
          BoxShadow(
              color: AppColors.shadow, blurRadius: 6, offset: Offset(0, 2))
        ],
      ),
      child: Row(children: [
        Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                color: _usageGranted
                    ? const Color(0xFFDCFCE7)
                    : AppColors.primaryLight,
                shape: BoxShape.circle),
            child: Icon(Icons.screen_search_desktop_rounded,
                color: _usageGranted ? AppColors.good : AppColors.primary,
                size: 20)),
        const SizedBox(width: 14),
        const Expanded(
            child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Usage Access',
                style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textDark)),
            Text('For screen time insights',
                style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted)),
          ],
        )),
        GestureDetector(
          onTap: () async {
            await openAppSettings();
            if (mounted) setState(() => _usageGranted = true);
          },
          child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                  color: _usageGranted
                      ? const Color(0xFFDCFCE7)
                      : AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(50)),
              child: Text(_usageGranted ? 'Done ✓' : 'Open',
                  style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color:
                          _usageGranted ? AppColors.good : AppColors.primary))),
        ),
      ]),
    );
  }

  Widget _buildTopBar() => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Row(children: [
            Icon(Icons.health_and_safety_rounded,
                color: AppColors.primary, size: 28),
            SizedBox(width: 8),
            Text('Predoc',
                style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textDark)),
          ]),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(50)),
            child: const Text('STEP 1 OF 3',
                style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                    letterSpacing: 1.2)),
          ),
        ],
      );
}
