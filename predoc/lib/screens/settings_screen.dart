// SettingsScreen — Day 9
//
// Added:
//   • Health Conditions section (Part 5) — user picks their condition,
//     thresholds are immediately refreshed in ContinuousAudioService
//   • Live Monitoring toggle (Day 8 — unchanged)
//   • Privacy section (Day 8 — unchanged)

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../theme/app_theme.dart';
import '../services/continuous_audio_service.dart';
import '../services/storage_service.dart';
import '../services/user_context_service.dart';
import '../app_services.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final ContinuousAudioService _continuousAudio = appContinuousAudio;

  bool _liveMonitoringOn  = false;
  bool _toggling          = false;
  HealthCondition _condition = HealthCondition.none;

  @override
  void initState() {
    super.initState();
    _liveMonitoringOn = StorageService.liveMonitoringEnabled;
    _condition        = UserContextService.getCondition();
  }

  // ─────────────────────────────────────────────────────────────
  // HEALTH CONDITION CHANGE
  // ─────────────────────────────────────────────────────────────

  Future<void> _onConditionChanged(HealthCondition? value) async {
    if (value == null) return;
    await UserContextService.setCondition(value);
    _continuousAudio.refreshThresholds();
    if (mounted) setState(() => _condition = value);

    final profile = UserContextService.getThresholds();
    debugPrint('[Settings] Condition changed to ${value.key} '
        '— cough=${profile.coughThreshold} '
        'sneeze=${profile.sneezeThreshold} '
        'snore=${profile.snoreThreshold}');
  }

  // ─────────────────────────────────────────────────────────────
  // TOGGLE LIVE MONITORING
  // ─────────────────────────────────────────────────────────────

  Future<void> _handleToggle(bool value) async {
    if (_toggling) return;

    if (value) {
      final confirmed = await _showPermissionDialog();
      if (!confirmed) return;

      final status = await Permission.microphone.request();
      if (!status.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Microphone permission is required for live monitoring.',
                style: TextStyle(fontFamily: 'Nunito'),
              ),
              backgroundColor: Color(0xFFEF4444),
            ),
          );
        }
        return;
      }

      setState(() => _toggling = true);
      try {
        if (!appModelService.isLoaded) {
          await appModelService.loadModels();
        }
        await _continuousAudio.start();
        await StorageService.setLiveMonitoringEnabled(true);
        if (mounted) setState(() { _liveMonitoringOn = true; _toggling = false; });
      } catch (e) {
        if (mounted) setState(() => _toggling = false);
        debugPrint('[Settings] Failed to start live monitoring: $e');
      }
    } else {
      setState(() => _toggling = true);
      try {
        await _continuousAudio.stop();
        await StorageService.setLiveMonitoringEnabled(false);
        if (mounted) setState(() { _liveMonitoringOn = false; _toggling = false; });
      } catch (e) {
        if (mounted) setState(() => _toggling = false);
      }
    }
  }

  Future<bool> _showPermissionDialog() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.all(24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: AppColors.primaryLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.mic_rounded,
                  color: AppColors.primary, size: 32),
            ),
            const SizedBox(height: 18),
            const Text(
              'Enable Live Health Monitoring?',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'This feature keeps the microphone active continuously to detect health signals like coughing, sneezing, and snoring.\n\n'
              '✓ All data stays on your device\n'
              '✓ No audio is recorded or stored\n'
              '✓ Only event counts are saved\n'
              '✓ A persistent notification will always be shown',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted,
                height: 1.6,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(
                    fontFamily: 'Nunito',
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enable',
                style: TextStyle(
                    fontFamily: 'Nunito', fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // ─────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.textDark, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Settings',
          style: TextStyle(
            fontFamily: 'Nunito',
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: AppColors.textDark,
          ),
        ),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        children: [
          // ── Section: Health Monitoring ────────────────────────
          _buildSectionHeader('Health Monitoring'),
          const SizedBox(height: 10),
          _buildLiveMonitoringTile(),

          const SizedBox(height: 28),

          // ── Section: Health Conditions (Part 5) ───────────────
          _buildSectionHeader('Health Conditions'),
          const SizedBox(height: 6),
          _buildConditionSubtitle(),
          const SizedBox(height: 10),
          _buildConditionSelector(),

          const SizedBox(height: 28),

          // ── Section: Privacy ──────────────────────────────────
          _buildSectionHeader('Privacy'),
          const SizedBox(height: 10),
          _buildInfoTile(
            icon: Icons.lock_outline_rounded,
            title: 'Data stays on device',
            subtitle:
                'No audio, health data, or personal info is ever uploaded.',
          ),
          const SizedBox(height: 10),
          _buildInfoTile(
            icon: Icons.mic_off_rounded,
            title: 'No audio recordings',
            subtitle:
                'Live monitoring only stores event counts — never raw audio.',
          ),
          const SizedBox(height: 10),
          _buildInfoTile(
            icon: Icons.notifications_active_outlined,
            title: 'Transparent notifications',
            subtitle:
                'A persistent notification is always shown when monitoring is active.',
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ── Live Monitoring Toggle Tile ───────────────────────────────

  Widget _buildLiveMonitoringTile() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _liveMonitoringOn
              ? AppColors.primary.withValues(alpha: 0.35)
              : AppColors.divider,
          width: 1.5,
        ),
        boxShadow: const [
          BoxShadow(
              color: AppColors.shadow, blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _liveMonitoringOn
                  ? AppColors.primaryLight
                  : const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _liveMonitoringOn
                  ? Icons.mic_rounded
                  : Icons.mic_off_rounded,
              color: _liveMonitoringOn
                  ? AppColors.primary
                  : AppColors.textMuted,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Live Health Monitoring',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textDark,
                    )),
                const SizedBox(height: 2),
                Text(
                  _liveMonitoringOn
                      ? 'Active — detecting cough, sneeze, snore'
                      : 'Off — tap to enable continuous monitoring',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _liveMonitoringOn
                        ? AppColors.primary
                        : AppColors.textMuted,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (_toggling)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primary,
              ),
            )
          else
            Switch(
              value: _liveMonitoringOn,
              onChanged: _handleToggle,
              activeThumbColor: AppColors.primary,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
        ],
      ),
    );
  }

  // ── Health Condition Selector (Part 5) ────────────────────────

  Widget _buildConditionSubtitle() {
    return Text(
      'Tell Predoc about your health so it can adjust detection sensitivity.',
      style: TextStyle(
        fontFamily: 'Nunito',
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.textMuted,
        height: 1.4,
      ),
    );
  }

  Widget _buildConditionSelector() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
              color: AppColors.shadow, blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      child: Column(
        children: HealthCondition.values.map((condition) {
          final isSelected = condition == _condition;
          final isLast =
              condition == HealthCondition.values.last;
          return Column(
            children: [
              InkWell(
                onTap: () => _onConditionChanged(condition),
                borderRadius: BorderRadius.vertical(
                  top: condition == HealthCondition.none
                      ? const Radius.circular(18)
                      : Radius.zero,
                  bottom: isLast ? const Radius.circular(18) : Radius.zero,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 14),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primaryLight
                        : Colors.transparent,
                    borderRadius: BorderRadius.vertical(
                      top: condition == HealthCondition.none
                          ? const Radius.circular(18)
                          : Radius.zero,
                      bottom:
                          isLast ? const Radius.circular(18) : Radius.zero,
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        condition.emoji,
                        style: const TextStyle(fontSize: 20),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              condition.label,
                              style: TextStyle(
                                fontFamily: 'Nunito',
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: isSelected
                                    ? AppColors.primary
                                    : AppColors.textDark,
                              ),
                            ),
                            Text(
                              condition.description,
                              style: const TextStyle(
                                fontFamily: 'Nunito',
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textMuted,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isSelected)
                        const Icon(Icons.check_circle_rounded,
                            color: AppColors.primary, size: 20)
                      else
                        const Icon(Icons.circle_outlined,
                            color: AppColors.divider, size: 20),
                    ],
                  ),
                ),
              ),
              if (!isLast)
                const Divider(
                    height: 1,
                    indent: 18,
                    endIndent: 18,
                    color: AppColors.divider),
            ],
          );
        }).toList(),
      ),
    );
  }

  // ── Shared helpers ────────────────────────────────────────────

  Widget _buildSectionHeader(String title) {
    return Text(
      title.toUpperCase(),
      style: const TextStyle(
        fontFamily: 'Nunito',
        fontSize: 11,
        fontWeight: FontWeight.w800,
        color: AppColors.textMuted,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
              color: AppColors.shadow, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.primary, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textDark,
                    )),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted,
                      height: 1.4,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
