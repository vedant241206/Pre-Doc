// DashboardService — Day 10
//
// Extended with:
//   • Pattern detection (7-day DailySnapshot analysis)
//   • Severity level in TodaySummary
//   • Day 10 strict health score formula via InsightService
//   • Auto-save DailySnapshot on each compute pass

import 'storage_service.dart';
import 'insight_service.dart';
import 'passive_monitoring_service.dart';

// ─────────────────────────────────────────────────────────────
// DATA MODELS
// ─────────────────────────────────────────────────────────────

class TodaySummary {
  final int score;
  final HealthColor color;
  final HealthSeverity severity;
  final int coughCount;
  final int sneezeCount;
  final int snoreCount;
  final bool hasData;
  final List<InsightMessage> messages;
  final List<HealthPattern> patterns;

  const TodaySummary({
    required this.score,
    required this.color,
    required this.severity,
    required this.coughCount,
    required this.sneezeCount,
    required this.snoreCount,
    required this.hasData,
    this.messages = const [],
    this.patterns = const [],
  });

  static const TodaySummary empty = TodaySummary(
    score:       0,
    color:       HealthColor.red,
    severity:    HealthSeverity.risk,
    coughCount:  0,
    sneezeCount: 0,
    snoreCount:  0,
    hasData:     false,
    messages:    [],
    patterns:    [],
  );
}

class WeeklySummary {
  final double avgScore;
  final int totalCough;
  final int totalSneeze;
  final int totalSnore;
  final String trend;       // "Improving ↑" | "Needs attention ↓" | "Stable →"
  final String dateRange;   // e.g. "Apr 9 – Apr 15"
  final bool hasData;
  final List<DayBar> bars; // 7 bars for the chart

  const WeeklySummary({
    required this.avgScore,
    required this.totalCough,
    required this.totalSneeze,
    required this.totalSnore,
    required this.trend,
    required this.dateRange,
    required this.hasData,
    required this.bars,
  });

  static const WeeklySummary empty = WeeklySummary(
    avgScore: 0,
    totalCough: 0,
    totalSneeze: 0,
    totalSnore: 0,
    trend: 'No data yet',
    dateRange: '',
    hasData: false,
    bars: <DayBar>[],
  );
}

class DayBar {
  final String label; // 'M', 'T', etc.
  final double fill;  // 0.0–1.0 (score / 100)
  final bool hasData;

  const DayBar({required this.label, required this.fill, required this.hasData});
}

// ─────────────────────────────────────────────────────────────
// SERVICE
// ─────────────────────────────────────────────────────────────

class DashboardService {
  const DashboardService();

  static const _insightSvc = InsightService();
  static const _dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  // ── TODAY SUMMARY ────────────────────────────────────────────

  TodaySummary computeToday(
    List<SessionResult> sessions, {
    PassiveMonitoringData? passive,
    // Day 10: live counts included
    int liveCough  = 0,
    int liveSneeze = 0,
    int liveSnore  = 0,
  }) {
    final todayStr = _dateKey(DateTime.now());
    final todaySessions = sessions
        .where((s) => _dateKey(_parseDate(s.sessionStart)) == todayStr)
        .toList();

    // Aggregate session counts
    int totalCough  = 0;
    int totalSneeze = 0;
    int totalSnore  = 0;
    for (final s in todaySessions) {
      totalCough  += s.coughCount;
      totalSneeze += s.sneezeCount;
      totalSnore  += s.snoreCount;
    }

    // Add live monitoring counts
    totalCough  += liveCough;
    totalSneeze += liveSneeze;
    totalSnore  += liveSnore;

    final bool hasAnyData = todaySessions.isNotEmpty ||
        liveCough > 0 || liveSneeze > 0 || liveSnore > 0;

    if (!hasAnyData && passive == null) return TodaySummary.empty;

    // Load 7-day snapshots for pattern detection
    final snapshots  = StorageService.getDailySnapshots(days: 7);
    final patterns   = _insightSvc.detectPatterns(snapshots);

    // Compute score using Day 10 strict formula
    final insight = _insightSvc.computeCombined(
      liveCoughCount:  totalCough,
      liveSneezeCount: totalSneeze,
      liveSnoreCount:  totalSnore,
      nightUsageRisk:  passive?.sleepRisk   ?? false,
      screenTimeRisk:  passive?.screenRisk  ?? false,
      lowActivity:     passive?.sedentary   ?? false,
      patterns:        patterns,
    );

    // Auto-save today's snapshot for future pattern detection
    _saveTodaySnapshot(
      cough:          totalCough,
      sneeze:         totalSneeze,
      snore:          totalSnore,
      score:          insight.score,
      nightUsageRisk: passive?.sleepRisk  ?? false,
      screenTimeRisk: passive?.screenRisk ?? false,
      lowActivity:    passive?.sedentary  ?? false,
    );

    return TodaySummary(
      score:       insight.score,
      color:       insight.color,
      severity:    insight.severity,
      coughCount:  totalCough,
      sneezeCount: totalSneeze,
      snoreCount:  totalSnore,
      hasData:     hasAnyData,
      messages:    insight.messages,
      patterns:    patterns,
    );
  }

  // ── WEEKLY SUMMARY ───────────────────────────────────────────

  WeeklySummary computeWeekly(List<SessionResult> sessions) {
    final now = DateTime.now();

    final Map<String, _AggDay> dayMap = {};

    for (final s in sessions) {
      final d = _parseDate(s.sessionStart);
      final diff = now.difference(d).inDays;
      if (diff < 0 || diff >= 7) continue;

      final key = _dateKey(d);
      dayMap.putIfAbsent(key, () => _AggDay());
      dayMap[key]!.add(s);
    }

    if (dayMap.isEmpty) return WeeklySummary.empty;

    // Build 7 bars (today is the rightmost)
    final bars = <DayBar>[];
    for (int i = 6; i >= 0; i--) {
      final day = now.subtract(Duration(days: i));
      final key = _dateKey(day);
      final agg = dayMap[key];
      final label = _dayLabels[day.weekday - 1];
      bars.add(DayBar(
        label:   label,
        fill:    agg != null ? (agg.avgScore / 100.0).clamp(0.0, 1.0) : 0.0,
        hasData: agg != null,
      ));
    }

    int tCough = 0, tSneeze = 0, tSnore = 0;
    double scoreSum = 0;
    int scoreDays   = 0;
    for (final agg in dayMap.values) {
      tCough  += agg.totalCough;
      tSneeze += agg.totalSneeze;
      tSnore  += agg.totalSnore;
      scoreSum += agg.avgScore;
      scoreDays++;
    }
    final avgScore = scoreDays > 0 ? scoreSum / scoreDays : 0.0;

    final String trend = _computeTrend(dayMap, now);

    final startDay = now.subtract(const Duration(days: 6));
    final dateRange = '${_monthDay(startDay)} – ${_monthDay(now)}';

    return WeeklySummary(
      avgScore:    avgScore,
      totalCough:  tCough,
      totalSneeze: tSneeze,
      totalSnore:  tSnore,
      trend:       trend,
      dateRange:   dateRange,
      hasData:     true,
      bars:        bars,
    );
  }

  // ── INSIGHTS ─────────────────────────────────────────────────

  List<InsightMessage> computeInsights(
    TodaySummary today, {
    PassiveMonitoringData? passive,
  }) {
    if (!today.hasData && passive == null) return [];
    // Return messages from already-computed TodaySummary (Day 10 format)
    if (today.messages.isNotEmpty) return today.messages.take(4).toList();

    // Fallback: recompute
    final result = _insightSvc.computeCombined(
      liveCoughCount:  today.coughCount,
      liveSneezeCount: today.sneezeCount,
      liveSnoreCount:  today.snoreCount,
      nightUsageRisk:  passive?.sleepRisk ?? false,
      screenTimeRisk:  passive?.screenRisk ?? false,
      lowActivity:     passive?.sedentary  ?? false,
    );
    return result.messages.take(4).toList();
  }

  // ── PATTERN DETECTION (Day 10) ───────────────────────────────

  List<HealthPattern> computePatterns() {
    final snapshots = StorageService.getDailySnapshots(days: 7);
    return _insightSvc.detectPatterns(snapshots);
  }

  // ── HELPERS ──────────────────────────────────────────────────

  /// Save today's snapshot to persistent storage for pattern detection.
  void _saveTodaySnapshot({
    required int  cough,
    required int  sneeze,
    required int  snore,
    required int  score,
    required bool nightUsageRisk,
    required bool screenTimeRisk,
    required bool lowActivity,
  }) {
    final snapshot = DailySnapshot(
      dateKey:       _dateKey(DateTime.now()),
      coughCount:    cough,
      sneezeCount:   sneeze,
      snoreCount:    snore,
      stepCount:     StorageService.todaySteps,
      healthScore:   score,
      nightUsageRisk: nightUsageRisk,
      screenTimeRisk: screenTimeRisk,
      lowActivity:   lowActivity,
    );
    // Fire-and-forget (sync not critical here)
    StorageService.saveDailySnapshot(snapshot);
  }

  String _computeTrend(Map<String, _AggDay> dayMap, DateTime now) {
    double last3  = 0, prev3 = 0;
    int    last3n = 0, prev3n = 0;

    for (int i = 0; i < 6; i++) {
      final day = now.subtract(Duration(days: i));
      final key = _dateKey(day);
      final agg = dayMap[key];
      if (agg == null) continue;
      if (i < 3) { last3 += agg.avgScore; last3n++; }
      else        { prev3 += agg.avgScore; prev3n++; }
    }

    if (last3n == 0 || prev3n == 0) return 'Stable →';

    final lastAvg = last3 / last3n;
    final prevAvg = prev3 / prev3n;
    if (lastAvg >= prevAvg + 3) return 'Improving ↑';
    if (lastAvg <= prevAvg - 3) return 'Needs attention ↓';
    return 'Stable →';
  }

  String _dateKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

  DateTime _parseDate(String iso) {
    try { return DateTime.parse(iso); }
    catch (_) { return DateTime.fromMillisecondsSinceEpoch(0); }
  }

  String _monthDay(DateTime d) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[d.month - 1]} ${d.day}';
  }
}

// ─────────────────────────────────────────────────────────────
// INTERNAL ACCUMULATOR
// ─────────────────────────────────────────────────────────────

class _AggDay {
  int    totalCough  = 0;
  int    totalSneeze = 0;
  int    totalSnore  = 0;
  double scoreSum    = 0;
  int    count       = 0;

  static const _insightSvc = InsightService();

  void add(SessionResult s) {
    totalCough  += s.coughCount;
    totalSneeze += s.sneezeCount;
    totalSnore  += s.snoreCount;
    final insight = _insightSvc.computeCombined(
      liveCoughCount:  s.coughCount,
      liveSneezeCount: s.sneezeCount,
      liveSnoreCount:  s.snoreCount,
      nightUsageRisk:  false,
      screenTimeRisk:  false,
      lowActivity:     false,
    );
    scoreSum += insight.score;
    count++;
  }

  double get avgScore => count > 0 ? scoreSum / count : 0.0;
}
