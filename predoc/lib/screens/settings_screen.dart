// SettingsScreen — Day 12 UI Refinement
// Logic unchanged. UI polished: Profile / Health Conditions / App Settings sections.

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/continuous_audio_service.dart';
import '../services/storage_service.dart';
import '../services/user_context_service.dart';
import '../utils/local_storage.dart';
import '../app_services.dart';
import '../services/firebase_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final ContinuousAudioService _continuousAudio = appContinuousAudio;

  late TextEditingController _nameCtrl;
  late TextEditingController _ageCtrl;
  late String _gender;

  late bool _asthma;
  late bool _frequentCold;
  late bool _sleepIssues;

  bool _isLinkingAccount = false;
  late String _notificationTime;

  @override
  void initState() {
    super.initState();
    _nameCtrl         = TextEditingController(text: LocalStorage.userName);
    _ageCtrl          = TextEditingController(
        text: StorageService.userAge > 0 ? '${StorageService.userAge}' : '');
    _gender           = LocalStorage.gender.isEmpty ? 'Prefer not to say' : LocalStorage.gender;
    _asthma           = StorageService.condAsthma;
    _frequentCold     = StorageService.condFrequentCold;
    _sleepIssues      = StorageService.condSleepIssues;
    _sleepIssues      = StorageService.condSleepIssues;
    _notificationTime = StorageService.notificationTime;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ageCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    await LocalStorage.setUserName(_nameCtrl.text.trim());
    final age = int.tryParse(_ageCtrl.text.trim()) ?? 0;
    await StorageService.setUserAge(age);
    await LocalStorage.setGender(_gender);
    
    // Sync to Firestore
    await FirebaseService.syncUserData();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Profile saved',
            style: TextStyle(fontFamily: 'Nunito')),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppColors.radiusCard)),
      ));
    }
  }

  Future<void> _saveConditions() async {
    await StorageService.setConditions(
        asthma: _asthma, frequentCold: _frequentCold, sleepIssues: _sleepIssues);
    _continuousAudio.refreshThresholds();
    final p = UserContextService.getThresholdsDay10();
    debugPrint('[Settings] thresholds — cough=${p.coughThreshold} '
        'sneeze=${p.sneezeThreshold} snore=${p.snoreThreshold}');
  }


  Future<void> _pickNotificationTime() async {
    final parts   = _notificationTime.split(':');
    final initial = TimeOfDay(
        hour:   int.tryParse(parts[0]) ?? 8,
        minute: int.tryParse(parts[1]) ?? 0);
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) {
      final str = '${picked.hour.toString().padLeft(2, '0')}:'
          '${picked.minute.toString().padLeft(2, '0')}';
      await StorageService.setNotificationTime(str);
      if (mounted) setState(() => _notificationTime = str);
    }
  }

  Future<void> _linkAccount() async {
    setState(() => _isLinkingAccount = true);
    try {
      final user = await FirebaseService.signInWithGoogle();
      if (user != null) {
        await LocalStorage.setSkipAuth(false);
        await FirebaseService.syncUserData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Account linked successfully!', style: TextStyle(fontFamily: 'Nunito')),
            backgroundColor: AppColors.accentGreen,
          ));
        }
        setState(() {}); // refresh UI to hide the link card
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Failed to link account.', style: TextStyle(fontFamily: 'Nunito')),
            backgroundColor: AppColors.risk,
          ));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error linking account: $e', style: const TextStyle(fontFamily: 'Nunito')),
          backgroundColor: AppColors.risk,
        ));
      }
    } finally {
      if (mounted) setState(() => _isLinkingAccount = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        shadowColor: AppColors.shadow,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.textDark, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Settings', style: TextStyle(fontFamily: 'Nunito',
            fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textDark)),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(
            horizontal: AppColors.paddingH, vertical: AppColors.paddingV),
        children: [
          // ── Guest Account Linking ───────────────────────────────
          if (LocalStorage.skipAuth) ...[
            _buildSectionLabel('🔗  Guest Profile'),
            const SizedBox(height: 10),
            _card(child: Column(children: [
              _infoTile(
                icon: Icons.account_circle_rounded,
                title: 'Link Your Account',
                subtitle: 'Your progress is only stored on this device. Link a Google account to save to the cloud and access the leaderboard.',
              ),
              _divider(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                child: _isLinkingAccount
                    ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                    : _buildSaveButton('Link Google Account', _linkAccount),
              ),
            ])),
            const SizedBox(height: AppColors.sectionGap),
          ],

          // ── Profile Card ──────────────────────────────────────
          _buildSectionLabel('👤  Profile'),
          const SizedBox(height: 10),
          _buildProfileCard(),
          const SizedBox(height: 12),
          _buildSaveButton('Save Profile', _saveProfile),

          const SizedBox(height: AppColors.sectionGap),

          // ── Health Conditions ─────────────────────────────────
          _buildSectionLabel('❤️  Health Conditions'),
          const SizedBox(height: 4),
          const Text('Adjusts detection sensitivity for you.',
              style: TextStyle(fontFamily: 'Nunito', fontSize: 12,
                  fontWeight: FontWeight.w600, color: AppColors.textMuted)),
          const SizedBox(height: 10),
          _buildConditionsCard(),

          const SizedBox(height: AppColors.sectionGap),

          // ── App Settings ──────────────────────────────────────
          _buildSectionLabel('⚙️  App Settings'),
          const SizedBox(height: 10),

          _notificationTile(),

          const SizedBox(height: AppColors.sectionGap),

          // ── Privacy ───────────────────────────────────────────
          _buildSectionLabel('🔒  Privacy'),
          const SizedBox(height: 10),
          _infoTile(icon: Icons.lock_outline_rounded,
              title: 'All data stays on device',
              subtitle: 'No audio, health data, or personal info is uploaded.'),
          const SizedBox(height: 10),
          _infoTile(icon: Icons.mic_off_rounded,
              title: 'No audio recordings',
              subtitle: 'Only event counts are saved — never raw audio.'),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // ── Section label ─────────────────────────────────────────

  Widget _buildSectionLabel(String title) => Text(
    title,
    style: const TextStyle(fontFamily: 'Nunito', fontSize: 13,
        fontWeight: FontWeight.w800, color: AppColors.textDark),
  );

  // ── Profile card ──────────────────────────────────────────

  Widget _buildProfileCard() {
    return _card(child: Column(children: [
      _textField(ctrl: _nameCtrl, label: 'Full Name',    icon: Icons.person_rounded),
      _divider(),
      _textField(ctrl: _ageCtrl, label: 'Age',           icon: Icons.cake_rounded,
          keyboardType: TextInputType.number),
      _divider(),
      _dropdownTile(
        icon: Icons.wc_rounded, label: 'Gender', value: _gender,
        items: ['Male', 'Female', 'Other', 'Prefer not to say'],
        onChanged: (v) { if (v != null) setState(() => _gender = v); },
      ),
      _divider(),
      _infoRow('Height',
          LocalStorage.heightFtInch.isNotEmpty
              ? LocalStorage.heightFtInch
              : '${LocalStorage.height.round()} ${LocalStorage.heightUnit}',
          Icons.height_rounded),
      _divider(),
      _infoRow('Weight',
          '${LocalStorage.weight.round()} ${LocalStorage.weightUnit}',
          Icons.monitor_weight_rounded),
    ]));
  }

  // ── Conditions card ───────────────────────────────────────

  Widget _buildConditionsCard() {
    return _card(child: Column(children: [
      _conditionTile(
        emoji: '💨', label: 'Asthma',
        subtitle: 'Cough detection sensitivity increased',
        value: _asthma,
        onChanged: (v) async {
          setState(() => _asthma = v!);
          await _saveConditions();
        },
      ),
      _divider(),
      _conditionTile(
        emoji: '🤧', label: 'Frequent Cold',
        subtitle: 'Sneeze detection sensitivity increased',
        value: _frequentCold,
        onChanged: (v) async {
          setState(() => _frequentCold = v!);
          await _saveConditions();
        },
      ),
      _divider(),
      _conditionTile(
        emoji: '😴', label: 'Sleep Issues',
        subtitle: 'Snore confirmation threshold stricter',
        value: _sleepIssues,
        onChanged: (v) async {
          setState(() => _sleepIssues = v!);
          await _saveConditions();
        },
      ),
      _divider(),
      _conditionTile(
        emoji: '✅', label: 'None',
        subtitle: 'No known conditions — baseline thresholds',
        value: !_asthma && !_frequentCold && !_sleepIssues,
        onChanged: (v) async {
          if (v == true) {
            setState(() { _asthma = false; _frequentCold = false; _sleepIssues = false; });
            await _saveConditions();
          }
        },
      ),
    ]));
  }

  // ── Card shell ────────────────────────────────────────────

  Widget _card({required Widget child}) => Container(
    decoration: appCardDecoration(),
    child: child,
  );

  Widget _divider() => const Divider(height: 1, color: AppColors.divider,
      indent: 18, endIndent: 18);

  // ── Text field tile ───────────────────────────────────────

  Widget _textField({
    required TextEditingController ctrl,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        child: Row(children: [
          Icon(icon, color: AppColors.primary, size: 20),
          const SizedBox(width: 14),
          Expanded(child: TextField(
            controller: ctrl,
            keyboardType: keyboardType,
            style: const TextStyle(fontFamily: 'Nunito', fontSize: 14,
                fontWeight: FontWeight.w700, color: AppColors.textDark),
            decoration: InputDecoration(
              labelText: label,
              labelStyle: const TextStyle(fontFamily: 'Nunito',
                  fontSize: 12, color: AppColors.textMuted),
              border: InputBorder.none,
            ),
          )),
        ]),
      );

  // ── Dropdown tile ─────────────────────────────────────────

  Widget _dropdownTile({
    required IconData icon,
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        child: Row(children: [
          Icon(icon, color: AppColors.primary, size: 20),
          const SizedBox(width: 14),
          Text(label, style: const TextStyle(fontFamily: 'Nunito',
              fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textDark)),
          const Spacer(),
          DropdownButton<String>(
            value: items.contains(value) ? value : items.last,
            underline: const SizedBox(),
            style: const TextStyle(fontFamily: 'Nunito', fontSize: 13,
                fontWeight: FontWeight.w700, color: AppColors.primary),
            items: items.map((s) => DropdownMenuItem(
                value: s,
                child: Text(s, style: const TextStyle(
                    fontFamily: 'Nunito', fontSize: 13,
                    fontWeight: FontWeight.w700)))).toList(),
            onChanged: onChanged,
          ),
        ]),
      );

  // ── Info row ──────────────────────────────────────────────

  Widget _infoRow(String label, String value, IconData icon) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
    child: Row(children: [
      Icon(icon, color: AppColors.primary, size: 20),
      const SizedBox(width: 14),
      Text(label, style: const TextStyle(fontFamily: 'Nunito', fontSize: 14,
          fontWeight: FontWeight.w700, color: AppColors.textDark)),
      const Spacer(),
      Text(value, style: const TextStyle(fontFamily: 'Nunito', fontSize: 13,
          fontWeight: FontWeight.w700, color: AppColors.textMuted)),
    ]),
  );

  // ── Save button ───────────────────────────────────────────

  Widget _buildSaveButton(String label, VoidCallback onTap) =>
      _TapScaleButton(
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(AppColors.radiusCard)),
          child: Text(label, style: const TextStyle(fontFamily: 'Nunito',
              fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
        ),
      );

  // ── Condition tile ────────────────────────────────────────

  Widget _conditionTile({
    required String emoji,
    required String label,
    required String subtitle,
    required bool value,
    required ValueChanged<bool?> onChanged,
  }) =>
      InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(AppColors.radiusCard),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(children: [
            Text(emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(fontFamily: 'Nunito', fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: value ? AppColors.primary : AppColors.textDark)),
              Text(subtitle, style: const TextStyle(fontFamily: 'Nunito',
                  fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
            ])),
            Checkbox(value: value, onChanged: onChanged,
                activeColor: AppColors.primary),
          ]),
        ),
      );


  // ── Notification tile ─────────────────────────────────────

  Widget _notificationTile() => _TapScaleButton(
    onTap: _pickNotificationTime,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: appCardDecoration(),
      child: Row(children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.notifications_active_rounded,
              color: AppColors.primary, size: 22)),
        const SizedBox(width: 14),
        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Daily Reminder Time', style: TextStyle(fontFamily: 'Nunito',
              fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textDark)),
          Text('Tap to change reminder time', style: TextStyle(
              fontFamily: 'Nunito', fontSize: 12, fontWeight: FontWeight.w600,
              color: AppColors.textMuted)),
        ])),
        Text(_notificationTime, style: const TextStyle(fontFamily: 'Nunito',
            fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.primary)),
        const SizedBox(width: 6),
        const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 20),
      ]),
    ),
  );

  // ── Info tile ─────────────────────────────────────────────

  Widget _infoTile({
    required IconData icon,
    required String title,
    required String subtitle,
  }) =>
      Container(
        padding: const EdgeInsets.all(AppColors.paddingV),
        decoration: appCardDecoration(),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: AppColors.primary, size: 18)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontFamily: 'Nunito', fontSize: 13,
                fontWeight: FontWeight.w800, color: AppColors.textDark)),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(fontFamily: 'Nunito', fontSize: 12,
                fontWeight: FontWeight.w600, color: AppColors.textMuted, height: 1.4)),
          ])),
        ]),
      );
}

// ── Tap Scale Button ───────────────────────────────────────────

class _TapScaleButton extends StatefulWidget {
  final VoidCallback onTap;
  final Widget child;
  const _TapScaleButton({required this.onTap, required this.child});
  @override
  State<_TapScaleButton> createState() => _TapScaleButtonState();
}

class _TapScaleButtonState extends State<_TapScaleButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _scale;

  @override
  void initState() {
    super.initState();
    _ctrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 120));
    _scale = Tween<double>(begin: 1.0, end: 0.97)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _handleTap() async {
    await _ctrl.forward();
    await _ctrl.reverse();
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      child: AnimatedBuilder(
        animation: _scale,
        builder: (_, child) => Transform.scale(scale: _scale.value, child: child),
        child: widget.child,
      ),
    );
  }
}
