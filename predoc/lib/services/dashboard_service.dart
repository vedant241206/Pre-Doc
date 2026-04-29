// DashboardService — Day 6 (extended Day 8)
//
// Pure, synchronous computation over stored SessionResult data.
// Call once per app-open; cache the result in HomeScreen state.
// No async, no side effects.

import 'storage_service.dart';
import 'insight_service.dart';
import 'passive_monitoring_service.dart';

// ─────────────────────────────────────────────────────────────
// DATA MODELS
// ─────────────────────────────────────────────────────────────

class TodaySummary {
  final int score;
  final HealthColor color;
  final int coughCount;
  final int sneezeCount;
  final int snoreCount;
  final bool hasData;

  const TodaySummary({
    required this.score,
    required this.color,
    required this.coughCount,
    required this.sneezeCount,
    required this.snoreCount,
    required this.hasData,
  });

  static const TodaySummary empty = TodaySummary(
    score: 0,
    color: HealthColor.red,
    coughCount: 0,
    sneezeCount: 0,
    snoreCount: 0,
    hasData: false,
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
  }) {
    final todayStr = _dateKey(DateTime.now());
    final todaySessions = sessions
        .where((s) => _dateKey(_parseDate(s.sessionStart)) == todayStr)
        .toList();

    if (todaySessions.isEmpty) return TodaySummary.empty;

    // Sum counts, use latest session for camera data
    int totalCough  = 0;
    int totalSneeze = 0;
    int totalSnore  = 0;
    for (final s in todaySessions) {
      totalCough  += s.coughCount;
      totalSneeze += s.sneezeCount;
      totalSnore  += s.snoreCount;
    }

    // Latest session (sessions are most-recent-first from getSessions())
    final latest = todaySessions.first;

      // Recompute score using summed counts + latest camera signals + passive flags
    final insight = _insightSvc.compute(
      coughCount:   totalCough,
      sneezeCount:  totalSneeze,
      snoreCount:   totalSnore,
      faceDetected: latest.faceDetected,
      brightness:   latest.brightnessValue,
      screenRisk:   passive?.screenRisk  ?? false,
      sleepRisk:    passive?.sleepRisk   ?? false,
      sedentary:    passive?.sedentary   ?? false,
    );

    return TodaySummary(
      score:       insight.score,
      color:       insight.color,
      coughCount:  totalCough,
      sneezeCount: totalSneeze,
      snoreCount:  totalSnore,
      hasData:     true,
    );
  }

  // ── WEEKLY SUMMARY ───────────────────────────────────────────

  WeeklySummary computeWeekly(List<SessionResult> sessions) {
    final now = DateTime.now();

    // Build a map: dateKey → aggregated counts + score for that day
    final Map<String, _AggDay> dayMap = {};

    for (final s in sessions) {
      final d = _parseDate(s.sessionStart);
      final diff = now.difference(d).inDays;
      if (diff < 0 || diff >= 7) continue; // only last 7 days

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
      final label = _dayLabels[day.weekday - 1]; // weekday: 1=Mon…7=Sun
      bars.add(DayBar(
        label:   label,
        fill:    agg != null ? (agg.avgScore / 100.0).clamp(0.0, 1.0) : 0.0,
        hasData: agg != null,
      ));
    }

    // Weekly totals
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

    // Trend: compare last 3 days vs previous 3 days
    final String trend = _computeTrend(dayMap, now);

    // Date range label
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

  /// Returns top insight messages based on today's aggregated data + passive flags.
  List<InsightMessage> computeInsights(
    TodaySummary today, {
    PassiveMonitoringData? passive,
  }) {
    if (!today.hasData && passive == null) return [];
    final result = _insightSvc.compute(
      coughCount:   today.coughCount,
      sneezeCount:  today.sneezeCount,
      snoreCount:   today.snoreCount,
      faceDetected: true, // don't penalize insights for camera quality
      brightness:   100.0,
      screenRisk:   passive?.screenRisk ?? false,
      sleepRisk:    passive?.sleepRisk  ?? false,
      sedentary:    passive?.sedentary  ?? false,
    );
    // Return at most 3 messages (Day 8 adds passive ones)
    return result.messages.take(3).toList();
  }

  // ── HELPERS ──────────────────────────────────────────────────

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
    final insight = _insightSvc.compute(
      coughCount:   s.coughCount,
      sneezeCount:  s.sneezeCount,
      snoreCount:   s.snoreCount,
      faceDetected: s.faceDetected,
      brightness:   s.brightnessValue,
    );
    scoreSum += insight.score;
    count++;
  }

  double get avgScore => count > 0 ? scoreSum / count : 0.0;
}
