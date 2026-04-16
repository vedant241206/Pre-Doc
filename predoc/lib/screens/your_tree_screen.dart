// ignore_for_file: prefer_const_constructors
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';
import '../services/storage_service.dart';
import '../services/insight_service.dart';
import '../services/dashboard_service.dart';

// ─────────────────────────────────────────────────────────────
// YOUR TREE SCREEN
// ─────────────────────────────────────────────────────────────

class YourTreeScreen extends StatefulWidget {
  const YourTreeScreen({super.key});

  @override
  State<YourTreeScreen> createState() => _YourTreeScreenState();
}

class _YourTreeScreenState extends State<YourTreeScreen>
    with TickerProviderStateMixin {
  // ── Data ──
  int _streak        = 0;
  int _todayScore    = 0;
  int _totalScore    = 0;
  bool _hasToday     = false;

  // ── Tree layer controllers ──
  // Each layer gets its own AnimationController so it can fire independently.
  late AnimationController _stemCtrl;
  late AnimationController _leaves1Ctrl;
  late AnimationController _leaves2Ctrl;
  late AnimationController _leaves3Ctrl;
  late AnimationController _crownCtrl;
  late AnimationController _shineCtrl;   // density/shine for streak >= 6

  late Animation<double> _stemAnim;      // height grow
  late Animation<double> _leaves1Anim;   // scale bounce
  late Animation<double> _leaves2Anim;
  late Animation<double> _leaves3Anim;
  late Animation<double> _crownAnim;
  late Animation<double> _shineAnim;

  static const _insightSvc  = InsightService();
  static const _dashSvc     = DashboardService();
  static const int _minScore = 60; // score threshold for streak day

  @override
  void initState() {
    super.initState();
    _initControllers();
    _computeData();
    _startAnimations();
  }

  void _initControllers() {
    // Stem grows upward → height 0→1
    _stemCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _stemAnim = CurvedAnimation(parent: _stemCtrl, curve: Curves.easeOut);

    // Leaves pop with bounce scale 0→1
    _leaves1Ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _leaves1Anim = CurvedAnimation(parent: _leaves1Ctrl, curve: Curves.elasticOut);

    _leaves2Ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _leaves2Anim = CurvedAnimation(parent: _leaves2Ctrl, curve: Curves.elasticOut);

    _leaves3Ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _leaves3Anim = CurvedAnimation(parent: _leaves3Ctrl, curve: Curves.elasticOut);

    _crownCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _crownAnim = CurvedAnimation(parent: _crownCtrl, curve: Curves.elasticOut);

    // Gentle pulse for density/shine
    _shineCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat(reverse: true);
    _shineAnim = CurvedAnimation(parent: _shineCtrl, curve: Curves.easeInOut);
  }

  // ── Compute streak + scores from session history ──────────────
  void _computeData() {
    final sessions = StorageService.getSessions(); // most-recent-first

    // Today data
    final today = _dashSvc.computeToday(sessions);
    _hasToday   = today.hasData;
    _todayScore = today.score;

    // Total score = sum of all session scores (capped per session by InsightService)
    int scoreSum = 0;
    for (final s in sessions) {
      final ins = _insightSvc.compute(
        coughCount:   s.coughCount,
        sneezeCount:  s.sneezeCount,
        snoreCount:   s.snoreCount,
        faceDetected: s.faceDetected,
        brightness:   s.brightnessValue,
      );
      scoreSum += ins.score;
    }
    _totalScore = scoreSum;

    // Streak = consecutive days (going back from today) where score >= 60
    _streak = _computeStreak(sessions);
  }

  int _computeStreak(List<SessionResult> sessions) {
    if (sessions.isEmpty) return 0;

    // Build map: dateKey → best score that day
    final Map<String, int> bestDay = {};
    for (final s in sessions) {
      DateTime dt;
      try { dt = DateTime.parse(s.sessionStart); }
      catch (_) { continue; }

      final key = '${dt.year}-${dt.month}-${dt.day}';
      final ins = _insightSvc.compute(
        coughCount:   s.coughCount,
        sneezeCount:  s.sneezeCount,
        snoreCount:   s.snoreCount,
        faceDetected: s.faceDetected,
        brightness:   s.brightnessValue,
      );
      final prev = bestDay[key] ?? 0;
      if (ins.score > prev) bestDay[key] = ins.score;
    }

    // Count from today backwards
    final now = DateTime.now();
    int streak = 0;
    for (int i = 0; i < 365; i++) {
      final d   = now.subtract(Duration(days: i));
      final key = '${d.year}-${d.month}-${d.day}';
      final score = bestDay[key] ?? 0;
      if (score >= _minScore) {
        streak++;
      } else {
        break;
      }
    }
    return streak;
  }

  // ── Fire animations sequentially based on streak ──────────────
  Future<void> _startAnimations() async {
    // Always show pot (static).
    // Delay slightly so build is complete.
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;

    // Day 1+: stem appears
    if (_streak >= 1) {
      await _stemCtrl.forward();
      await Future.delayed(const Duration(milliseconds: 100));
    }

    // Day 3+: leaves level 1
    if (_streak >= 3) {
      await _leaves1Ctrl.forward();
      await Future.delayed(const Duration(milliseconds: 80));
    }

    // Day 4+: leaves level 2
    if (_streak >= 4) {
      await _leaves2Ctrl.forward();
      await Future.delayed(const Duration(milliseconds: 80));
    }

    // Day 5+: leaves level 3
    if (_streak >= 5) {
      await _leaves3Ctrl.forward();
      await Future.delayed(const Duration(milliseconds: 80));
    }

    // Day 5+: crown
    if (_streak >= 5) {
      await _crownCtrl.forward();
    }
    // Streak 6+ → shine already pulsing via repeat
  }

  @override
  void dispose() {
    _stemCtrl.dispose();
    _leaves1Ctrl.dispose();
    _leaves2Ctrl.dispose();
    _leaves3Ctrl.dispose();
    _crownCtrl.dispose();
    _shineCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildHeader(),
          const SizedBox(height: 28),
          _buildTreeStage(),
          const SizedBox(height: 28),
          _buildStreakRow(),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // HEADER — today score + total score + trophy
  // ─────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your Tree',
              style: const TextStyle(
                fontFamily: 'Nunito',
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                _ScorePill(
                  label: 'Today',
                  value: _hasToday ? '$_todayScore' : '--',
                  color: _hasToday
                      ? (_todayScore >= 80
                          ? AppColors.accentGreen
                          : _todayScore >= 50
                              ? const Color(0xFFF59E0B)
                              : AppColors.accentRed)
                      : AppColors.textMuted,
                ),
                const SizedBox(width: 8),
                _ScorePill(
                  label: 'Total XP',
                  value: '$_totalScore',
                  color: AppColors.primary,
                ),
              ],
            ),
          ],
        ),
        // Trophy / leaderboard icon — tappable
        GestureDetector(
          onTap: () => context.push('/leaderboard'),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFBBF24).withValues(alpha: 0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(Icons.emoji_events_rounded,
                color: Color(0xFFB45309), size: 26),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  // TREE STAGE — the animated plant
  // ─────────────────────────────────────────────────────────────

  Widget _buildTreeStage() {
    // Stem height grows from 0 → 120 px based on streak (taller with more days)
    final stemMaxH = math.min(60.0 + _streak * 14.0, 140.0);

    return Container(
      width: double.infinity,
      height: 320,
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: const Color(0xFFBBF7D0),
          width: 1.5,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            // ── POT (always visible) ──
            Positioned(
              bottom: 8,
              child: _TreePot(),
            ),

            // ── STEM (streak >= 1) ──
            if (_streak >= 1)
              Positioned(
                bottom: 56, // above pot
                child: AnimatedBuilder(
                  animation: _stemAnim,
                  builder: (_, __) {
                    final h = stemMaxH * _stemAnim.value;
                    return Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        width: _streak >= 3 ? 12 : 10,
                        height: h,
                        decoration: BoxDecoration(
                          color: const Color(0xFF4D7C0F),
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF84CC16).withValues(alpha: 0.3),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

            // ── LEAVES LEVEL 1 (streak >= 3) ──
            if (_streak >= 3)
              AnimatedBuilder(
                animation: _leaves1Anim,
                builder: (_, child) => Positioned(
                  bottom: 56 + stemMaxH * 0.35,
                  child: Transform.scale(
                    scale: _leaves1Anim.value,
                    child: child,
                  ),
                ),
                child: _LeafPair(
                  size: 48,
                  color: const Color(0xFF16A34A),
                  angle: 0.5,
                ),
              ),

            // ── LEAVES LEVEL 2 (streak >= 4) ──
            if (_streak >= 4)
              AnimatedBuilder(
                animation: _leaves2Anim,
                builder: (_, child) => Positioned(
                  bottom: 56 + stemMaxH * 0.6,
                  child: Transform.scale(
                    scale: _leaves2Anim.value,
                    child: child,
                  ),
                ),
                child: _LeafPair(
                  size: 56,
                  color: const Color(0xFF22C55E),
                  angle: -0.4,
                ),
              ),

            // ── LEAVES LEVEL 3 (streak >= 5) ──
            if (_streak >= 5)
              AnimatedBuilder(
                animation: _leaves3Anim,
                builder: (_, child) => Positioned(
                  bottom: 56 + stemMaxH * 0.75,
                  child: Transform.scale(
                    scale: _leaves3Anim.value,
                    child: child,
                  ),
                ),
                child: _LeafPair(
                  size: 44,
                  color: const Color(0xFF4ADE80),
                  angle: 0.3,
                ),
              ),

            // ── CROWN (streak >= 5) ──
            if (_streak >= 5)
              AnimatedBuilder(
                animation: _crownAnim,
                builder: (_, child) => Positioned(
                  bottom: 56 + stemMaxH * 0.88,
                  child: Transform.scale(
                    scale: _crownAnim.value,
                    child: child,
                  ),
                ),
                child: _Crown(
                  hasShine: _streak >= 6,
                  shineAnim: _shineAnim,
                ),
              ),

            // ── EMPTY SEED STATE (no streak) ──
            if (_streak == 0)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Text('🌱', style: TextStyle(fontSize: 48)),
                    SizedBox(height: 10),
                    Text(
                      'Your seed is waiting…',
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF166534),
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Score ≥ 60 today to start growing',
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF4ADE80),
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

  // _buildStars() removed — Day 7 tree cleanup

  // ─────────────────────────────────────────────────────────────
  // STREAK ROW
  // ─────────────────────────────────────────────────────────────

  Widget _buildStreakRow() {
    final stageLabel = _streak == 0
        ? 'Plant your seed'
        : _streak == 1
            ? 'Sprouting 🌱'
            : _streak <= 3
                ? 'Growing 🌿'
                : _streak <= 5
                    ? 'Blooming 🌳'
                    : 'Thriving 🌟';

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Streak fire badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _streak > 0
                ? const Color(0xFFFEF3C7)
                : AppColors.primaryLight,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _streak > 0 ? '🔥' : '💤',
                style: const TextStyle(fontSize: 20),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$_streak day${_streak == 1 ? '' : 's'}',
                    style: const TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textDark,
                    ),
                  ),
                  Text(
                    'STREAK',
                    style: const TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMuted,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Stage label
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Text(
            stageLabel,
            style: const TextStyle(
              fontFamily: 'Nunito',
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// SCORE PILL WIDGET
// ─────────────────────────────────────────────────────────────

class _ScorePill extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _ScorePill({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(50),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// TREE POT — always visible
// ─────────────────────────────────────────────────────────────

class _TreePot extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(64, 44),
      painter: _PotPainter(),
    );
  }
}

class _PotPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;

    // Rim
    final rimPaint = Paint()..color = const Color(0xFF92400E);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, 8), width: size.width, height: 14),
        const Radius.circular(4),
      ),
      rimPaint,
    );

    // Body (trapezoid via path)
    final bodyPaint = Paint()..color = const Color(0xFFB45309);
    final body = Path()
      ..moveTo(cx - 26, 14)
      ..lineTo(cx - 18, size.height)
      ..lineTo(cx + 18, size.height)
      ..lineTo(cx + 26, 14)
      ..close();
    canvas.drawPath(body, bodyPaint);

    // Highlight
    final hlPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawLine(Offset(cx - 18, 16), Offset(cx - 12, size.height - 4), hlPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

// ─────────────────────────────────────────────────────────────
// LEAF PAIR — two curved leaves left + right
// ─────────────────────────────────────────────────────────────

class _LeafPair extends StatelessWidget {
  final double size;
  final Color color;
  final double angle; // tilt

  const _LeafPair({
    required this.size,
    required this.color,
    required this.angle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Left leaf
        Transform.rotate(
          angle: -math.pi / 4 - angle,
          child: CustomPaint(
            size: Size(size, size),
            painter: _LeafPainter(color: color, veinAlpha: 0.25),
          ),
        ),
        SizedBox(width: size * 0.1),
        // Right leaf (mirrored)
        Transform.scale(
          scaleX: -1,
          child: Transform.rotate(
            angle: -math.pi / 4 - angle,
            child: CustomPaint(
              size: Size(size, size),
              painter: _LeafPainter(color: color, veinAlpha: 0.25),
            ),
          ),
        ),
      ],
    );
  }
}

class _LeafPainter extends CustomPainter {
  final Color color;
  final double veinAlpha;
  const _LeafPainter({required this.color, required this.veinAlpha});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final paint = Paint()..color = color;

    final path = Path()
      ..moveTo(w * 0.5, h)
      ..cubicTo(0, h * 0.7, 0, 0, w * 0.5, 0)
      ..cubicTo(w, 0, w, h * 0.7, w * 0.5, h)
      ..close();
    canvas.drawPath(path, paint);

    // Centre vein
    final veinPaint = Paint()
      ..color = Colors.white.withValues(alpha: veinAlpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(w * 0.5, h * 0.9), Offset(w * 0.5, h * 0.1), veinPaint);
  }

  @override
  bool shouldRepaint(covariant _LeafPainter old) => old.color != color;
}

// ─────────────────────────────────────────────────────────────
// CROWN — the top cluster of leaves
// ─────────────────────────────────────────────────────────────

class _Crown extends StatelessWidget {
  final bool hasShine;
  final Animation<double> shineAnim;

  const _Crown({required this.hasShine, required this.shineAnim});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: shineAnim,
      builder: (_, __) {
        final glowOpacity = hasShine ? (0.3 + shineAnim.value * 0.35) : 0.2;
        return CustomPaint(
          size: const Size(100, 88),
          painter: _CrownPainter(glowOpacity: glowOpacity),
        );
      },
    );
  }
}

class _CrownPainter extends CustomPainter {
  final double glowOpacity;
  const _CrownPainter({required this.glowOpacity});

  static const _layers = [
    Color(0xFF14532D),
    Color(0xFF166534),
    Color(0xFF15803D),
    Color(0xFF16A34A),
    Color(0xFF22C55E),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.55;

    // Draw 5 concentric leaf rosettes from back to front
    for (int l = 0; l < _layers.length; l++) {
      final scale = 1.0 - l * 0.15;
      final offset = l * 0.18;
      _drawRosette(canvas, cx, cy, scale, _layers[l], angleOffset: offset);
    }

    // Glow ring on top
    final glowPaint = Paint()
      ..color = const Color(0xFF86EFAC).withValues(alpha: glowOpacity)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
    canvas.drawCircle(Offset(cx, cy), 28, glowPaint);
  }

  void _drawRosette(Canvas canvas, double cx, double cy, double scale,
      Color color, {double angleOffset = 0}) {
    const n = 7;
    final paint = Paint()..color = color;
    for (int i = 0; i < n; i++) {
      final angle = (i * 2 * math.pi / n) + angleOffset;
      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(angle);
      final lw = 22.0 * scale;
      final lh = 38.0 * scale;
      final path = Path()
        ..moveTo(0, 0)
        ..cubicTo(-lw, -lh * 0.4, -lw * 0.8, -lh, 0, -lh * 1.1)
        ..cubicTo(lw * 0.8, -lh, lw, -lh * 0.4, 0, 0)
        ..close();
      canvas.drawPath(path, paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _CrownPainter old) =>
      old.glowOpacity != glowOpacity;
}
