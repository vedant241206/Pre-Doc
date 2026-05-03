// ignore_for_file: prefer_const_constructors
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';
import '../services/storage_service.dart';
import '../services/insight_service.dart';
import '../services/dashboard_service.dart';

class YourTreeScreen extends StatefulWidget {
  const YourTreeScreen({super.key});
  @override
  State<YourTreeScreen> createState() => _YourTreeScreenState();
}

class _YourTreeScreenState extends State<YourTreeScreen>
    with TickerProviderStateMixin {
  int _streak = 0;
  int _todayScore = 0;
  int _totalScore = 0;
  bool _hasToday = false;

  // Growth controllers
  late AnimationController _stemCtrl;
  late AnimationController _leaves1Ctrl;
  late AnimationController _leaves2Ctrl;
  late AnimationController _leaves3Ctrl;
  late AnimationController _crownCtrl;

  // Continuous: sway + shine
  late AnimationController _swayCtrl;
  late AnimationController _shineCtrl;

  late Animation<double> _stemAnim;
  late Animation<double> _leaves1Anim;
  late Animation<double> _leaves2Anim;
  late Animation<double> _leaves3Anim;
  late Animation<double> _crownAnim;
  late Animation<double> _swayAnim; // -1 → +1 sway
  late Animation<double> _shineAnim;

  static const _dashSvc = DashboardService();

  // ── Score-based growth stage thresholds ─────────────────────
  // Stage 0: seed   (0 pts)
  // Stage 1: stem   (1+ pts)
  // Stage 2: leaves1 (80+ pts)
  // Stage 3: leaves2 (200+ pts)
  // Stage 4: leaves3 (400+ pts)
  // Stage 5: crown  (700+ pts)
  int get _growthStage {
    if (_totalScore >= 700) return 5;
    if (_totalScore >= 400) return 4;
    if (_totalScore >= 200) return 3;
    if (_totalScore >= 80) return 2;
    if (_totalScore >= 1) return 1;
    return 0;
  }

  @override
  void initState() {
    super.initState();
    _initControllers();
    _computeData();
    _startAnimations();
  }

  void _initControllers() {
    _stemCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _stemAnim = CurvedAnimation(parent: _stemCtrl, curve: Curves.easeOut);

    _leaves1Ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _leaves1Anim =
        CurvedAnimation(parent: _leaves1Ctrl, curve: Curves.elasticOut);

    _leaves2Ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _leaves2Anim =
        CurvedAnimation(parent: _leaves2Ctrl, curve: Curves.elasticOut);

    _leaves3Ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _leaves3Anim =
        CurvedAnimation(parent: _leaves3Ctrl, curve: Curves.elasticOut);

    _crownCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _crownAnim = CurvedAnimation(parent: _crownCtrl, curve: Curves.elasticOut);

    // Gentle sway: -1 → +1 (maps to a small rotation)
    _swayCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2200))
      ..repeat(reverse: true);
    _swayAnim = Tween<double>(begin: -1.0, end: 1.0)
        .animate(CurvedAnimation(parent: _swayCtrl, curve: Curves.easeInOut));

    // Shine pulse for streak >= 6
    _shineCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat(reverse: true);
    _shineAnim = CurvedAnimation(parent: _shineCtrl, curve: Curves.easeInOut);
  }

  void _computeData() {
    // 1. Calculate today's score using live counts
    final liveCounts = StorageService.getDailyLiveCounts();
    final today = _dashSvc.computeToday(
      [], // no legacy sessions
      liveCough: liveCounts['cough'] ?? 0,
      liveSneeze: liveCounts['sneeze'] ?? 0,
      liveSnore: liveCounts['snore'] ?? 0,
    );

    _hasToday = today.hasData;
    _todayScore = today.score;

    // 2. Calculate total score and streak from DailySnapshots
    final snapshots = StorageService.getDailySnapshots(days: 365);
    int scoreSum = 0;
    for (final s in snapshots) {
      scoreSum += s.healthScore;
    }
    // Also add today's score to total if today isn't saved in snapshots yet
    // Actually, DashboardService.computeToday saves the snapshot automatically!
    _totalScore = scoreSum > 0 ? scoreSum : (today.hasData ? today.score : 0);
    _streak = _computeStreak(snapshots, today.hasData, today.score);
  }

  int _computeStreak(
      List<DailySnapshot> snapshots, bool hasToday, int todayScore) {
    if (snapshots.isEmpty && !hasToday) return 0;

    final Map<String, int> bestDay = {};
    for (final s in snapshots) {
      bestDay[s.dateKey] = s.healthScore;
    }

    if (hasToday) {
      final now = DateTime.now();
      final todayKey = '${now.year}-${now.month}-${now.day}';
      bestDay[todayKey] = todayScore;
    }

    final now = DateTime.now();
    int streak = 0;
    for (int i = 0; i < 365; i++) {
      final d = now.subtract(Duration(days: i));
      final key = '${d.year}-${d.month}-${d.day}';
      if ((bestDay[key] ?? 0) >= 60) {
        streak++;
      } else {
        // Allow breaking on today if they haven't completed a session yet today, but check yesterday
        if (i == 0) continue;
        break;
      }
    }
    return streak;
  }

  Future<void> _startAnimations() async {
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    if (_growthStage >= 1) {
      await _stemCtrl.forward();
      await Future.delayed(const Duration(milliseconds: 100));
    }
    if (_growthStage >= 2) {
      await _leaves1Ctrl.forward();
      await Future.delayed(const Duration(milliseconds: 80));
    }
    if (_growthStage >= 3) {
      await _leaves2Ctrl.forward();
      await Future.delayed(const Duration(milliseconds: 80));
    }
    if (_growthStage >= 4) {
      await _leaves3Ctrl.forward();
      await Future.delayed(const Duration(milliseconds: 80));
    }
    if (_growthStage >= 5) {
      await _crownCtrl.forward();
    }
  }

  @override
  void dispose() {
    _stemCtrl.dispose();
    _leaves1Ctrl.dispose();
    _leaves2Ctrl.dispose();
    _leaves3Ctrl.dispose();
    _crownCtrl.dispose();
    _swayCtrl.dispose();
    _shineCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          AppColors.paddingH, AppColors.paddingV, AppColors.paddingH, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildHeader(),
          const SizedBox(height: AppColors.sectionGap),
          _buildTreeStage(),
          const SizedBox(height: AppColors.sectionGap),
          _buildStreakRow(),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Your Tree',
              style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textDark)),
          const SizedBox(height: 4),
          Row(children: [
            _ScorePill(
              label: 'Today',
              value: _hasToday ? '$_todayScore' : '--',
              color: _hasToday
                  ? (_todayScore >= 80
                      ? AppColors.good
                      : _todayScore >= 50
                          ? AppColors.moderate
                          : AppColors.risk)
                  : AppColors.textMuted,
            ),
            const SizedBox(width: 8),
            _ScorePill(
                label: 'Total XP',
                value: '$_totalScore',
                color: AppColors.primary),
          ]),
        ]),
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
                    color: const Color(0xFFFBBF24).withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 3))
              ],
            ),
            child: const Icon(Icons.emoji_events_rounded,
                color: Color(0xFFB45309), size: 26),
          ),
        ),
      ],
    );
  }

  Widget _buildTreeStage() {
    final stemMaxH = math.min(60.0 + _growthStage * 16.0, 140.0);

    return Container(
      width: double.infinity,
      height: 320,
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(AppColors.radiusCard + 4),
        border: Border.all(color: const Color(0xFFBBF7D0), width: 1.5),
        boxShadow: const [
          BoxShadow(
              color: AppColors.shadow, blurRadius: 8, offset: Offset(0, 3))
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppColors.radiusCard + 4),
        child: AnimatedBuilder(
          animation: _swayAnim,
          builder: (_, child) {
            // Sway only if there's a stem
            final swayRad = _streak >= 1
                ? _swayAnim.value * 0.03 // ±1.7 degrees
                : 0.0;
            return Stack(
              alignment: Alignment.bottomCenter,
              children: [
                // Tree group with sway (rotates around pot top)
                Positioned(
                  bottom: 40, // above pot
                  child: Transform.rotate(
                    angle: swayRad,
                    alignment: Alignment.bottomCenter,
                    child: SizedBox(
                      width: 200,
                      height: 260,
                      child: Stack(
                        alignment: Alignment.bottomCenter,
                        children: [
                          // STEM
                          if (_growthStage >= 1)
                            AnimatedBuilder(
                              animation: _stemAnim,
                              builder: (_, __) {
                                final h = stemMaxH * _stemAnim.value;
                                return Positioned(
                                  bottom: 0,
                                  child: Container(
                                    width: _streak >= 3 ? 12 : 10,
                                    height: h,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF4D7C0F),
                                      borderRadius: BorderRadius.circular(6),
                                      boxShadow: [
                                        BoxShadow(
                                            color: const Color(0xFF84CC16)
                                                .withValues(alpha: 0.3),
                                            blurRadius: 6)
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),

                          // DEPTH LAYER: back leaves (growthStage>=2, slightly smaller/darker)
                          if (_growthStage >= 2)
                            AnimatedBuilder(
                              animation: _leaves1Anim,
                              builder: (_, child) => Positioned(
                                bottom: stemMaxH * 0.28,
                                child: Opacity(
                                  opacity: (_leaves1Anim.value).clamp(0.0, 1.0),
                                  child: Transform.scale(
                                    scale: (_leaves1Anim.value * 0.75)
                                        .clamp(0, 1.5),
                                    child: child,
                                  ),
                                ),
                              ),
                              child: _LeafPair(
                                  size: 38,
                                  color: const Color(0xFF166534),
                                  angle: 0.6),
                            ),

                          // LEAVES LEVEL 1 — front
                          if (_growthStage >= 2)
                            AnimatedBuilder(
                              animation: _leaves1Anim,
                              builder: (_, child) => Positioned(
                                bottom: stemMaxH * 0.35,
                                child: Opacity(
                                  opacity: (_leaves1Anim.value).clamp(0.0, 1.0),
                                  child: Transform.scale(
                                    scale: _leaves1Anim.value.clamp(0, 1.5),
                                    child: child,
                                  ),
                                ),
                              ),
                              child: _LeafPair(
                                  size: 50,
                                  color: const Color(0xFF16A34A),
                                  angle: 0.5),
                            ),

                          // DEPTH LAYER: back leaves 2
                          if (_growthStage >= 3)
                            AnimatedBuilder(
                              animation: _leaves2Anim,
                              builder: (_, child) => Positioned(
                                bottom: stemMaxH * 0.52,
                                child: Opacity(
                                  opacity: (_leaves2Anim.value).clamp(0.0, 1.0),
                                  child: Transform.scale(
                                    scale: (_leaves2Anim.value * 0.75)
                                        .clamp(0, 1.5),
                                    child: child,
                                  ),
                                ),
                              ),
                              child: _LeafPair(
                                  size: 44,
                                  color: const Color(0xFF15803D),
                                  angle: -0.5),
                            ),

                          // LEAVES LEVEL 2 — front
                          if (_growthStage >= 3)
                            AnimatedBuilder(
                              animation: _leaves2Anim,
                              builder: (_, child) => Positioned(
                                bottom: stemMaxH * 0.60,
                                child: Opacity(
                                  opacity: (_leaves2Anim.value).clamp(0.0, 1.0),
                                  child: Transform.scale(
                                    scale: _leaves2Anim.value.clamp(0, 1.5),
                                    child: child,
                                  ),
                                ),
                              ),
                              child: _LeafPair(
                                  size: 58,
                                  color: const Color(0xFF22C55E),
                                  angle: -0.4),
                            ),

                          // LEAVES LEVEL 3
                          if (_growthStage >= 4)
                            AnimatedBuilder(
                              animation: _leaves3Anim,
                              builder: (_, child) => Positioned(
                                bottom: stemMaxH * 0.75,
                                child: Opacity(
                                  opacity: (_leaves3Anim.value).clamp(0.0, 1.0),
                                  child: Transform.scale(
                                    scale: _leaves3Anim.value.clamp(0, 1.5),
                                    child: child,
                                  ),
                                ),
                              ),
                              child: _LeafPair(
                                  size: 44,
                                  color: const Color(0xFF4ADE80),
                                  angle: 0.3),
                            ),

                          // CROWN
                          if (_growthStage >= 5)
                            AnimatedBuilder(
                              animation: _crownAnim,
                              builder: (_, child) => Positioned(
                                bottom: stemMaxH * 0.88,
                                child: Opacity(
                                  opacity: (_crownAnim.value).clamp(0.0, 1.0),
                                  child: Transform.scale(
                                    scale: _crownAnim.value.clamp(0, 1.5),
                                    child: child,
                                  ),
                                ),
                              ),
                              child: _Crown(
                                  hasShine: _growthStage >= 5,
                                  shineAnim: _shineAnim),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),

                // POT with shadow beneath
                Positioned(
                  bottom: 0,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Pot shadow ellipse
                      Container(
                        width: 72,
                        height: 10,
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF000000).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(50),
                        ),
                      ),
                      const SizedBox(height: 2),
                      _TreePot(),
                    ],
                  ),
                ),

                // SEED STATE — always shows when no score yet
                if (_growthStage == 0)
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Text('🌱', style: TextStyle(fontSize: 52)),
                        SizedBox(height: 10),
                        Text('Your seed is waiting…',
                            style: TextStyle(
                                fontFamily: 'Nunito',
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF166534))),
                        SizedBox(height: 4),
                        Text('Complete a session to start growing',
                            style: TextStyle(
                                fontFamily: 'Nunito',
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF4ADE80))),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildStreakRow() {
    final stageLabel = _growthStage == 0
        ? 'Plant your seed'
        : _growthStage == 1
            ? 'Sprouting 🌱'
            : _growthStage == 2
                ? 'Growing 🌿'
                : _growthStage == 3
                    ? 'Blooming 🌳'
                    : _growthStage == 4
                        ? 'Flourishing 🌺'
                        : 'Thriving 🌟';

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color:
                _streak > 0 ? const Color(0xFFFEF3C7) : AppColors.primaryLight,
            borderRadius: BorderRadius.circular(AppColors.radiusCard),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(_streak > 0 ? '🔥' : '💤',
                style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$_streak day${_streak == 1 ? '' : 's'}',
                  style: const TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textDark)),
              const Text('STREAK',
                  style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMuted,
                      letterSpacing: 1)),
            ]),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(AppColors.radiusCard),
            boxShadow: [
              BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.25),
                  blurRadius: 8,
                  offset: const Offset(0, 3))
            ],
          ),
          child: Text(stageLabel,
              style: const TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
        ),
      ],
    );
  }
}

// ── Score Pill ─────────────────────────────────────────────────

class _ScorePill extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _ScorePill(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(50),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label,
            style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color)),
        const SizedBox(width: 5),
        Text(value,
            style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: color)),
      ]),
    );
  }
}

// ── Tree Pot ───────────────────────────────────────────────────

class _TreePot extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: const Size(64, 44), painter: _PotPainter());
}

class _PotPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    // Rim
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(cx, 8), width: size.width, height: 14),
          const Radius.circular(4)),
      Paint()..color = const Color(0xFF92400E),
    );
    // Body
    final body = Path()
      ..moveTo(cx - 26, 14)
      ..lineTo(cx - 18, size.height)
      ..lineTo(cx + 18, size.height)
      ..lineTo(cx + 26, 14)
      ..close();
    canvas.drawPath(body, Paint()..color = const Color(0xFFB45309));
    // Highlight
    canvas.drawLine(
      Offset(cx - 18, 16),
      Offset(cx - 12, size.height - 4),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

// ── Leaf Pair ──────────────────────────────────────────────────

class _LeafPair extends StatelessWidget {
  final double size;
  final Color color;
  final double angle;
  const _LeafPair(
      {required this.size, required this.color, required this.angle});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Transform.rotate(
        angle: -math.pi / 4 - angle,
        child: CustomPaint(
            size: Size(size, size),
            painter: _LeafPainter(color: color, veinAlpha: 0.22)),
      ),
      SizedBox(width: size * 0.08),
      Transform.scale(
        scaleX: -1,
        child: Transform.rotate(
          angle: -math.pi / 4 - angle,
          child: CustomPaint(
              size: Size(size, size),
              painter: _LeafPainter(color: color, veinAlpha: 0.22)),
        ),
      ),
    ]);
  }
}

class _LeafPainter extends CustomPainter {
  final Color color;
  final double veinAlpha;
  const _LeafPainter({required this.color, required this.veinAlpha});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(w * 0.5, h)
      ..cubicTo(0, h * 0.7, 0, 0, w * 0.5, 0)
      ..cubicTo(w, 0, w, h * 0.7, w * 0.5, h)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawLine(
      Offset(w * 0.5, h * 0.9),
      Offset(w * 0.5, h * 0.1),
      Paint()
        ..color = Colors.white.withValues(alpha: veinAlpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _LeafPainter old) => old.color != color;
}

// ── Crown ──────────────────────────────────────────────────────

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
            painter: _CrownPainter(glowOpacity: glowOpacity));
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
    final cx = size.width / 2, cy = size.height * 0.55;
    for (int l = 0; l < _layers.length; l++) {
      _drawRosette(canvas, cx, cy, 1.0 - l * 0.15, _layers[l],
          angleOffset: l * 0.18);
    }
    canvas.drawCircle(
      Offset(cx, cy),
      28,
      Paint()
        ..color = const Color(0xFF86EFAC).withValues(alpha: glowOpacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
    );
  }

  void _drawRosette(
      Canvas canvas, double cx, double cy, double scale, Color color,
      {double angleOffset = 0}) {
    const n = 7;
    for (int i = 0; i < n; i++) {
      final angle = (i * 2 * math.pi / n) + angleOffset;
      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(angle);
      final lw = 22.0 * scale, lh = 38.0 * scale;
      canvas.drawPath(
        Path()
          ..moveTo(0, 0)
          ..cubicTo(-lw, -lh * 0.4, -lw * 0.8, -lh, 0, -lh * 1.1)
          ..cubicTo(lw * 0.8, -lh, lw, -lh * 0.4, 0, 0)
          ..close(),
        Paint()..color = color,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _CrownPainter old) =>
      old.glowOpacity != glowOpacity;
}
