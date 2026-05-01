import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';
import '../utils/local_storage.dart';

class BasicInfoScreen extends StatefulWidget {
  const BasicInfoScreen({super.key});

  @override
  State<BasicInfoScreen> createState() => _BasicInfoScreenState();
}

class _BasicInfoScreenState extends State<BasicInfoScreen>
    with TickerProviderStateMixin {
  // ── Progress bar ──
  late AnimationController _progressController;
  late Animation<double> _progressAnim;
  // ── Name ──
  final TextEditingController _nameCtrl = TextEditingController();

  // ── Gender ──
  String _selectedGender = '';

  // ── Date of Birth ──
  DateTime? _dob;
  int? _calculatedAge;
  final TextEditingController _dobController = TextEditingController();

  // ── Height ──
  String _heightUnit = 'cm'; // 'cm' or 'ft'
  final TextEditingController _heightCmCtrl = TextEditingController();
  final TextEditingController _heightFtCtrl = TextEditingController();
  final TextEditingController _heightInCtrl = TextEditingController();

  // ── Weight ──
  double _weightKg = 65.0;
  String _weightUnit = 'kg';

  // ── Submission state ──
  bool _submitted = false;
  bool _isLoading = false;

  // ── Error map ──
  final Map<String, String?> _errors = {
    'name':    null,
    'gender':  null,
    'dob':     null,
    'height':  null,
    'country': null,
    'city':    null,
  };

  // ── Location ──
  final TextEditingController _countryCtrl = TextEditingController();
  final TextEditingController _cityCtrl    = TextEditingController();

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _progressAnim = Tween<double>(begin: 0.0, end: 0.5).animate(
      CurvedAnimation(parent: _progressController, curve: Curves.easeInOut),
    );

    // Pre-fill from storage if existing
    _nameCtrl.text = LocalStorage.userName;
    _selectedGender = LocalStorage.gender;
    final savedDob = LocalStorage.dob;
    if (savedDob.isNotEmpty) {
      try {
        _dob = DateTime.parse(savedDob);
        _dobController.text = _formatDate(_dob!);
        _calculatedAge = _ageFrom(_dob!);
      } catch (_) {}
    }
    _heightUnit = LocalStorage.heightUnit;
    final h = LocalStorage.height;
    if (_heightUnit == 'cm') {
      if (h > 0) _heightCmCtrl.text = h.toStringAsFixed(0);
    } else {
      final ftInch = LocalStorage.heightFtInch;
      if (ftInch.isNotEmpty) {
        final parts = ftInch.split("'");
        if (parts.length == 2) {
          _heightFtCtrl.text = parts[0];
          _heightInCtrl.text = parts[1];
        }
      }
    }
    _weightKg   = LocalStorage.weight;
    _weightUnit = LocalStorage.weightUnit;

    // Pre-fill country/city
    _countryCtrl.text = LocalStorage.country;
    _cityCtrl.text    = LocalStorage.city;
  }

  @override
  void dispose() {
    _progressController.dispose();
    _nameCtrl.dispose();
    _dobController.dispose();
    _heightCmCtrl.dispose();
    _heightFtCtrl.dispose();
    _heightInCtrl.dispose();
    _countryCtrl.dispose();
    _cityCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ──
  int _ageFrom(DateTime dob) {
    final now = DateTime.now();
    int age = now.year - dob.year;
    if (now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day)) {
      age--;
    }
    return age;
  }

  String _formatDate(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}/${d.year}';

  double get _displayWeight =>
      _weightUnit == 'kg' ? _weightKg : _weightKg * 2.20462;

  double get _weightSliderMin => _weightUnit == 'kg' ? 20.0 : 44.0;
  double get _weightSliderMax => _weightUnit == 'kg' ? 200.0 : 440.0;

  // ── Validation ──
  bool _validate() {
    bool ok = true;
    setState(() {
      _errors['name'] =
          _nameCtrl.text.trim().isEmpty ? 'Please enter your name' : null;
      _errors['gender'] =
          _selectedGender.isEmpty ? 'Please select your gender' : null;
      _errors['dob'] = _dob == null ? 'Please enter your date of birth' : null;

      if (_heightUnit == 'cm') {
        final raw = double.tryParse(_heightCmCtrl.text);
        if (raw == null || raw < 50 || raw > 280) {
          _errors['height'] = 'Enter a valid height (50–280 cm)';
          ok = false;
        } else {
          _errors['height'] = null;
        }
      } else {
        final ft = int.tryParse(_heightFtCtrl.text);
        final inch = int.tryParse(_heightInCtrl.text);
        if (ft == null || ft < 1 || ft > 9) {
          _errors['height'] = 'Enter valid feet (1–9)';
          ok = false;
        } else if (inch == null || inch < 0 || inch > 11) {
          _errors['height'] = 'Enter valid inches (0–11)';
          ok = false;
        } else {
          _errors['height'] = null;
        }
      }

      _errors['country'] = _countryCtrl.text.trim().isEmpty
          ? 'Please enter your country' : null;
      _errors['city'] = _cityCtrl.text.trim().isEmpty
          ? 'Please enter your city' : null;

      if (_errors['name']   != null)  ok = false;
      if (_errors['gender'] != null)  ok = false;
      if (_errors['dob']    != null)  ok = false;
      if (_errors['country'] != null) ok = false;
      if (_errors['city']    != null) ok = false;
    });
    return ok;
  }

  // ── Submit ──
  Future<void> _onSubmit() async {
    if (!_validate()) return;
    setState(() => _isLoading = true);

    // Save name
    await LocalStorage.setUserName(_nameCtrl.text.trim());

    // Save gender
    await LocalStorage.setGender(_selectedGender);

    // Save DOB
    await LocalStorage.setDob(_dob!.toIso8601String());

    // Save height
    await LocalStorage.setHeightUnit(_heightUnit);
    if (_heightUnit == 'cm') {
      await LocalStorage.setHeight(double.parse(_heightCmCtrl.text));
    } else {
      final ft = int.parse(_heightFtCtrl.text);
      final inch = int.parse(_heightInCtrl.text.isEmpty ? '0' : _heightInCtrl.text);
      final totalCm = (ft * 30.48) + (inch * 2.54);
      await LocalStorage.setHeight(totalCm);
      await LocalStorage.setHeightFtInch("$ft'$inch");
    }

    // Save weight
    await LocalStorage.setWeightUnit(_weightUnit);
    final kgToSave = _weightUnit == 'kg' ? _weightKg : _weightKg;
    await LocalStorage.setWeight(kgToSave);

    // Save country + city
    await LocalStorage.setCountry(_countryCtrl.text.trim());
    await LocalStorage.setCity(_cityCtrl.text.trim());

    // Mark done
    await LocalStorage.setBasicInfoDone();

    // Animate progress bar
    _progressController.forward();
    setState(() {
      _submitted = true;
      _isLoading = false;
    });

    // Wait for animation + show success then navigate
    await Future.delayed(const Duration(milliseconds: 1400));

    if (mounted) {
      _showSuccessSnackbar();
      await Future.delayed(const Duration(milliseconds: 900));
      if (mounted) context.go('/device_test');
    }
  }

  void _showSuccessSnackbar() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.accentGreen,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        duration: const Duration(milliseconds: 1800),
        content: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.white, size: 22),
            SizedBox(width: 10),
            Text(
              'Profile saved! Your tree is growing 🌱',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontWeight: FontWeight.w700,
                color: Colors.white,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── DOB picker ──
  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 25, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: DateTime(now.year - 1),
      builder: (ctx, child) {
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              surface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _dob = picked;
        _dobController.text = _formatDate(picked);
        _calculatedAge = _ageFrom(picked);
        _errors['dob'] = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Fixed top area (header + progress) ──
            _buildTopArea(),
            // ── Scrollable form ──
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildNameSection(),
                    const SizedBox(height: 28),
                    _buildGenderSection(),
                    const SizedBox(height: 28),
                    _buildDobSection(),
                    const SizedBox(height: 28),
                    _buildHeightSection(),
                    const SizedBox(height: 28),
                    _buildWeightSection(),
                    const SizedBox(height: 28),
                    _buildLocationSection(),
                    const SizedBox(height: 32),
                    _buildDeviceTestSection(),
                    const SizedBox(height: 32),
                    _buildSubmitButton(),
                    const SizedBox(height: 12),
                    const Center(
                      child: Text(
                        'You can update these details later in Settings.',
                        style: TextStyle(
                          fontFamily: 'Nunito',
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // TOP AREA
  // ─────────────────────────────────────────────
  Widget _buildTopArea() {
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.health_and_safety_rounded,
                      color: AppColors.primary, size: 26),
                  SizedBox(width: 6),
                  Text(
                    'Predoc',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textDark,
                    ),
                  ),
                ],
              ),
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: AppColors.primaryLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person_rounded,
                    color: AppColors.primary, size: 22),
              ),
            ],
          ),
          const SizedBox(height: 18),
          // ── Step label ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(50),
            ),
            child: const Text(
              'STEP 1 OF 4',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppColors.textMid,
                letterSpacing: 1.2,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Basic Info',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textDark,
                ),
              ),
              AnimatedBuilder(
                animation: _progressAnim,
                builder: (_, __) => Text(
                  '${(_progressAnim.value * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // ── Progress bar ──
          ClipRRect(
            borderRadius: BorderRadius.circular(50),
            child: AnimatedBuilder(
              animation: _progressAnim,
              builder: (_, __) => LinearProgressIndicator(
                value: _progressAnim.value,
                minHeight: 8,
                backgroundColor: AppColors.divider,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // NAME SECTION
  // ─────────────────────────────────────────────
  Widget _buildNameSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('What is your name?'),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: _errors['name'] != null
                  ? AppColors.accentRed
                  : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.person_rounded,
                  color: AppColors.primary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) =>
                      setState(() => _errors['name'] = null),
                  style: const TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'e.g. Alex',
                    hintStyle: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_errors['name'] != null) ...[
          const SizedBox(height: 6),
          _errorText(_errors['name']!),
        ],
      ],
    );
  }

  // ─────────────────────────────────────────────
  // GENDER SECTION
  // ─────────────────────────────────────────────
  Widget _buildGenderSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('What is your gender?'),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: _genderPill('Male', Icons.male_rounded)),
            const SizedBox(width: 12),
            Expanded(child: _genderPill('Female', Icons.female_rounded)),
            const SizedBox(width: 12),
            Expanded(child: _genderPill('Other', Icons.transgender_rounded)),
          ],
        ),
        if (_errors['gender'] != null) ...[
          const SizedBox(height: 6),
          _errorText(_errors['gender']!),
        ],
      ],
    );
  }

  Widget _genderPill(String label, IconData icon) {
    final isSelected = _selectedGender == label;
    return GestureDetector(
      onTap: () => setState(() {
        _selectedGender = label;
        _errors['gender'] = null;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.divider,
            width: isSelected ? 0 : 1.5,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.28),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  )
                ]
              : [
                  const BoxShadow(
                    color: AppColors.shadow,
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  )
                ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 30,
              color: isSelected ? Colors.white : AppColors.primary,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isSelected ? Colors.white : AppColors.textDark,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // DATE OF BIRTH SECTION
  // ─────────────────────────────────────────────
  Widget _buildDobSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('What is your date of birth?'),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: _pickDob,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: _errors['dob'] != null
                    ? AppColors.accentRed
                    : AppColors.divider,
                width: 1.5,
              ),
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
                const Icon(Icons.calendar_month_rounded,
                    color: AppColors.primary, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _dobController.text.isEmpty
                        ? 'mm/dd/yyyy'
                        : _dobController.text,
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _dobController.text.isEmpty
                          ? AppColors.textMuted
                          : AppColors.textDark,
                    ),
                  ),
                ),
                if (_calculatedAge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: Text(
                      '$_calculatedAge yrs',
                      style: const TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  )
                else
                  const Icon(Icons.chevron_right_rounded,
                      color: AppColors.textMuted, size: 22),
              ],
            ),
          ),
        ),
        if (_errors['dob'] != null) ...[
          const SizedBox(height: 6),
          _errorText(_errors['dob']!),
        ],
      ],
    );
  }

  // ─────────────────────────────────────────────
  // HEIGHT SECTION
  // ─────────────────────────────────────────────
  Widget _buildHeightSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _sectionLabel('What is your height?'),
            _unitToggle(
              leftLabel: 'CM',
              rightLabel: 'FT',
              selectedLeft: _heightUnit == 'cm',
              onToggle: (bool leftSelected) {
                setState(() {
                  _heightUnit = leftSelected ? 'cm' : 'ft';
                  _errors['height'] = null;
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 14),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, anim) =>
              FadeTransition(opacity: anim, child: child),
          child: _heightUnit == 'cm'
              ? _heightCmField()
              : _heightFtInchFields(),
        ),
        if (_errors['height'] != null) ...[
          const SizedBox(height: 6),
          _errorText(_errors['height']!),
        ],
      ],
    );
  }

  Widget _heightCmField() {
    return _styledTextField(
      key: const ValueKey('cm'),
      controller: _heightCmCtrl,
      hint: '175',
      suffix: 'cm',
      keyboardType: const TextInputType.numberWithOptions(decimal: false),
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(3),
      ],
      onChanged: (_) => setState(() => _errors['height'] = null),
    );
  }

  Widget _heightFtInchFields() {
    return Row(
      key: const ValueKey('ft'),
      children: [
        Expanded(
          child: _styledTextField(
            controller: _heightFtCtrl,
            hint: '5',
            suffix: 'ft',
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(1),
            ],
            onChanged: (_) => setState(() => _errors['height'] = null),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _styledTextField(
            controller: _heightInCtrl,
            hint: '11',
            suffix: 'in',
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(2),
            ],
            onChanged: (_) => setState(() => _errors['height'] = null),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────
  // WEIGHT SECTION
  // ─────────────────────────────────────────────
  Widget _buildWeightSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _sectionLabel('What is your weight?'),
            _unitToggle(
              leftLabel: 'KG',
              rightLabel: 'LBS',
              selectedLeft: _weightUnit == 'kg',
              onToggle: (bool leftSelected) {
                setState(() {
                  if (leftSelected && _weightUnit != 'kg') {
                    // lbs → kg
                    _weightKg = _weightKg / 2.20462;
                  } else if (!leftSelected && _weightUnit == 'kg') {
                    // kg stays internal, display switches
                  }
                  _weightUnit = leftSelected ? 'kg' : 'lbs';
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                color: AppColors.shadow,
                blurRadius: 10,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            children: [
              // Large number display
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _displayWeight.toStringAsFixed(1),
                    style: const TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 48,
                      fontWeight: FontWeight.w900,
                      color: AppColors.primary,
                      height: 1,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _weightUnit,
                      style: const TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textLight,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Slider
              SliderTheme(
                data: SliderThemeData(
                  activeTrackColor: AppColors.primary,
                  inactiveTrackColor: AppColors.divider,
                  thumbColor: AppColors.primary,
                  overlayColor: AppColors.primary.withValues(alpha: 0.12),
                  trackHeight: 5,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 12),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 22),
                ),
                child: Slider(
                  value: _displayWeight.clamp(_weightSliderMin, _weightSliderMax),
                  min: _weightSliderMin,
                  max: _weightSliderMax,
                  divisions: (_weightSliderMax - _weightSliderMin).toInt() * 2,
                  onChanged: (val) {
                    setState(() {
                      if (_weightUnit == 'kg') {
                        _weightKg = val;
                      } else {
                        _weightKg = val / 2.20462;
                      }
                    });
                  },
                ),
              ),
              // Tick labels
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _weightSliderMin.toStringAsFixed(0),
                      style: const TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                    Text(
                      _weightSliderMax.toStringAsFixed(0),
                      style: const TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────
  // LOCATION SECTION — country + city for leaderboard
  // ─────────────────────────────────────────────
  Widget _buildLocationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Where are you from?'),
        const SizedBox(height: 6),
        const Text(
          'Used for leaderboard country & city filters.',
          style: TextStyle(
            fontFamily: 'Nunito',
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 14),
        // Country field
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: _errors['country'] != null
                  ? AppColors.accentRed
                  : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.flag_rounded,
                  color: AppColors.primary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _countryCtrl,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) =>
                      setState(() => _errors['country'] = null),
                  style: const TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'e.g. India',
                    hintStyle: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_errors['country'] != null) ...[
          const SizedBox(height: 6),
          _errorText(_errors['country']!),
        ],
        const SizedBox(height: 14),
        // City field
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: _errors['city'] != null
                  ? AppColors.accentRed
                  : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.location_city_rounded,
                  color: AppColors.primary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _cityCtrl,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) =>
                      setState(() => _errors['city'] = null),
                  style: const TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'e.g. Mumbai',
                    hintStyle: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_errors['city'] != null) ...[
          const SizedBox(height: 6),
          _errorText(_errors['city']!),
        ],
      ],
    );
  }

  // ─────────────────────────────────────────────
  // DEVICE TEST SECTION (UI only)
  // ─────────────────────────────────────────────
  Widget _buildDeviceTestSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider, width: 1),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.biotech_rounded,
                  color: Color(0xFFB45309),
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Device Test',
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textDark,
                      ),
                    ),
                    Text(
                      'Run a quick hardware check on your device',
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _deviceTestItem(Icons.camera_alt_rounded, 'Camera'),
              const SizedBox(width: 10),
              _deviceTestItem(Icons.mic_rounded, 'Mic'),
              const SizedBox(width: 10),
              _deviceTestItem(Icons.sensors_rounded, 'Sensors'),
            ],
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () {
              context.go('/device_test');
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(50),
                border: Border.all(color: AppColors.primary, width: 1.5),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.play_circle_rounded,
                      color: AppColors.primary, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Run Device Test',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _deviceTestItem(IconData icon, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.primaryLight,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.primary, size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                fontFamily: 'Nunito',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // SUBMIT BUTTON
  // ─────────────────────────────────────────────
  Widget _buildSubmitButton() {
    return GestureDetector(
      onTap: (_isLoading || _submitted) ? null : _onSubmit,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
        decoration: BoxDecoration(
          color: _submitted
              ? AppColors.accentGreen
              : _isLoading
                  ? AppColors.primaryMid
                  : AppColors.primaryDark,
          borderRadius: BorderRadius.circular(50),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isLoading) ...[
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2.5),
              ),
              const SizedBox(width: 12),
            ],
            Text(
              _submitted
                  ? '✓ Profile Saved!'
                  : _isLoading
                      ? 'Saving...'
                      : 'Submit Profile',
              style: const TextStyle(
                fontFamily: 'Nunito',
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 0.3,
              ),
            ),
            if (!_isLoading && !_submitted) ...[
              const SizedBox(width: 10),
              const Icon(Icons.arrow_forward_rounded,
                  color: Colors.white, size: 20),
            ],
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // SHARED HELPERS
  // ─────────────────────────────────────────────
  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: 'Nunito',
        fontSize: 17,
        fontWeight: FontWeight.w800,
        color: AppColors.textDark,
      ),
    );
  }

  Widget _errorText(String msg) {
    return Row(
      children: [
        const Icon(Icons.error_outline_rounded,
            size: 14, color: AppColors.accentRed),
        const SizedBox(width: 5),
        Text(
          msg,
          style: const TextStyle(
            fontFamily: 'Nunito',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.accentRed,
          ),
        ),
      ],
    );
  }

  Widget _styledTextField({
    Key? key,
    required TextEditingController controller,
    required String hint,
    String? suffix,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    ValueChanged<String>? onChanged,
  }) {
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _errors['height'] != null
              ? AppColors.accentRed
              : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              inputFormatters: inputFormatters,
              onChanged: onChanged,
              style: const TextStyle(
                fontFamily: 'Nunito',
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: hint,
                hintStyle: const TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                ),
              ),
            ),
          ),
          if (suffix != null)
            Text(
              suffix,
              style: const TextStyle(
                fontFamily: 'Nunito',
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textLight,
              ),
            ),
        ],
      ),
    );
  }

  Widget _unitToggle({
    required String leftLabel,
    required String rightLabel,
    required bool selectedLeft,
    required ValueChanged<bool> onToggle,
  }) {
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(50),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _toggleSegment(leftLabel, selectedLeft, () => onToggle(true)),
          _toggleSegment(rightLabel, !selectedLeft, () => onToggle(false)),
        ],
      ),
    );
  }

  Widget _toggleSegment(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(50),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Nunito',
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: active ? Colors.white : AppColors.textLight,
          ),
        ),
      ),
    );
  }
}
