import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/storage_service.dart';
import '../services/dashboard_service.dart';
import '../services/notification_service.dart';
import '../services/insight_service.dart';
import 'your_tree_screen.dart';
import 'ask_ai_screen.dart';
import 'med_checkup_screen.dart';
import 'nearby_docs_screen.dart';
// ignore_for_file: prefer_const_constructors

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedTab = 0;

  // ── Dashboard data (cached — not recomputed every frame) ──
  late TodaySummary  _today;
  late WeeklySummary _weekly;
  late List<InsightMessage> _insights;

  static const _dashboard = DashboardService();

  final List<_NavItem> _navItems = [
    _NavItem(icon: Icons.home_rounded,             label: 'HOME'),
    _NavItem(icon: Icons.park_rounded,             label: 'YOUR TREE'),
    _NavItem(icon: Icons.smart_toy_rounded,        label: 'ASK AI'),
    _NavItem(icon: Icons.medical_services_rounded, label: 'MED CHECKUP'),
    _NavItem(icon: Icons.location_on_rounded,      label: 'NEARBY DOCS'),
  ];

  @override
  void initState() {
    super.initState();
    _loadDashboard();
    // Show daily notification after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService.maybeShowDailyBanner(context, _today);
    });
  }

  /// Synchronous — SessionResult data is already loaded in SharedPreferences.
  void _loadDashboard() {
    final sessions = StorageService.getSessions();
    _today   = _dashboard.computeToday(sessions);
    _weekly  = _dashboard.computeWeekly(sessions);
    _insights = _dashboard.computeInsights(_today);
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      _buildHomeTab(),
      const YourTreeScreen(),
      const AskAiScreen(),
      const MedCheckupScreen(),
      const NearbyDocsScreen(),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: IndexedStack(
          index: _selectedTab,
          children: pages,
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // HOME TAB
  // ─────────────────────────────────────────────────────────────

  Widget _buildHomeTab() {
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async {
        setState(_loadDashboard);
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _buildHeader()),
          SliverToBoxAdapter(child: _buildTodaySection()),
          SliverToBoxAdapter(child: _buildWeeklySection()),
          SliverToBoxAdapter(child: _buildInsightsSection()),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // HEADER
  // ─────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning 🌅'
        : hour < 17
            ? 'Good afternoon ☀️'
            : 'Good evening 🌙';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                greeting,
                style: const TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 2),
              const Row(
                children: [
                  Icon(Icons.health_and_safety_rounded,
                      color: AppColors.primary, size: 24),
                  SizedBox(width: 6),
                  Text(
                    'Predoc',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textDark,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: AppColors.primaryDark,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person_rounded,
                color: Colors.white, size: 22),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // TODAY SECTION
  // ─────────────────────────────────────────────────────────────

  Widget _buildTodaySection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Today's Health",
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textDark,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Text(
                  _today.hasData ? 'Live Data' : 'No Data Yet',
                  style: const TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (!_today.hasData) ...[
            _EmptyStateCard(
              icon: Icons.health_and_safety_outlined,
              title: 'No data yet',
              subtitle: 'Complete your device test to see your health score.',
            ),
          ] else ...[
            // Health score card (big, coloured)
            _HealthScoreCard(score: _today.score, color: _today.color),
            const SizedBox(height: 14),
            // Cough / Sneeze / Snore count row
            Row(
              children: [
                Expanded(
                    child: _CountCard(
                  icon: '🤧',
                  label: 'COUGH',
                  count: _today.coughCount,
                  accentColor: const Color(0xFFEF4444),
                )),
                const SizedBox(width: 10),
                Expanded(
                    child: _CountCard(
                  icon: '🤲',
                  label: 'SNEEZE',
                  count: _today.sneezeCount,
                  accentColor: const Color(0xFFF59E0B),
                )),
                const SizedBox(width: 10),
                Expanded(
                    child: _CountCard(
                  icon: '😴',
                  label: 'SNORE',
                  count: _today.snoreCount,
                  accentColor: const Color(0xFF8B5CF6),
                )),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // WEEKLY SECTION
  // ─────────────────────────────────────────────────────────────

  Widget _buildWeeklySection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Past 7 Days',
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 14),
          if (!_weekly.hasData) ...[
            _EmptyStateCard(
              icon: Icons.bar_chart_rounded,
              title: 'No weekly data',
              subtitle: 'Complete a few sessions to see weekly trends.',
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(
                      color: AppColors.shadow,
                      blurRadius: 10,
                      offset: Offset(0, 3))
                ],
              ),
              child: Column(
                children: [
                  // Top row — trend + date range
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _weekly.trend,
                            style: TextStyle(
                              fontFamily: 'Nunito',
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: _weekly.trend.contains('↑')
                                  ? AppColors.accentGreen
                                  : _weekly.trend.contains('↓')
                                      ? AppColors.accentRed
                                      : AppColors.textDark,
                            ),
                          ),
                          const Text(
                            'WEEKLY TREND',
                            style: TextStyle(
                              fontFamily: 'Nunito',
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textMuted,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          const Icon(Icons.calendar_today_rounded,
                              size: 14, color: AppColors.textMuted),
                          const SizedBox(width: 5),
                          Text(
                            _weekly.dateRange,
                            style: const TextStyle(
                              fontFamily: 'Nunito',
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Weekly bar chart
                  _WeeklyBarChart(bars: _weekly.bars),
                  const SizedBox(height: 20),
                  // Weekly totals row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _WeekStat(
                          label: 'Avg Score',
                          value: _weekly.avgScore.round().toString(),
                          icon: Icons.favorite_rounded,
                          color: AppColors.primary),
                      _WeekStat(
                          label: 'Coughs',
                          value: _weekly.totalCough.toString(),
                          icon: Icons.air_rounded,
                          color: const Color(0xFFEF4444)),
                      _WeekStat(
                          label: 'Sneezes',
                          value: _weekly.totalSneeze.toString(),
                          icon: Icons.water_drop_rounded,
                          color: const Color(0xFFF59E0B)),
                      _WeekStat(
                          label: 'Snores',
                          value: _weekly.totalSnore.toString(),
                          icon: Icons.bedtime_rounded,
                          color: const Color(0xFF8B5CF6)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // INSIGHTS SECTION
  // ─────────────────────────────────────────────────────────────

  Widget _buildInsightsSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Insights',
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 14),
          if (_insights.isEmpty) ...[
            _EmptyStateCard(
              icon: Icons.lightbulb_outline_rounded,
              title: 'No insights yet',
              subtitle: 'Complete your device test to get personalised tips.',
            ),
          ] else ...[
            for (int i = 0; i < _insights.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              _InsightCard(msg: _insights[i]),
            ],
          ],
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // BOTTOM NAV (unchanged from Day 1–5)
  // ─────────────────────────────────────────────────────────────

  Widget _buildBottomNav() {
    return Container(
      height: 80,
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(_navItems.length, (i) {
          final item = _navItems[i];
          final isActive = _selectedTab == i;
          return GestureDetector(
            onTap: () => setState(() => _selectedTab = i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isActive ? AppColors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(50),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    item.icon,
                    size: 22,
                    color: isActive ? Colors.white : AppColors.textMuted,
                  ),
                  if (isActive) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.label,
                      style: const TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// NAV ITEM MODEL
// ─────────────────────────────────────────────────────────────

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}

// ─────────────────────────────────────────────────────────────
// HEALTH SCORE CARD — coloured by band
// ─────────────────────────────────────────────────────────────

class _HealthScoreCard extends StatelessWidget {
  final int score;
  final HealthColor color;

  const _HealthScoreCard({required this.score, required this.color});

  Color get _bg {
    switch (color) {
      case HealthColor.green:  return const Color(0xFF22C55E);
      case HealthColor.yellow: return const Color(0xFFF59E0B);
      case HealthColor.red:    return const Color(0xFFEF4444);
    }
  }

  String get _label {
    switch (color) {
      case HealthColor.green:  return 'Great — keep it up! 🎉';
      case HealthColor.yellow: return 'Fair — room to improve';
      case HealthColor.red:    return 'Needs attention ⚠️';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
              color: _bg.withValues(alpha: 0.38),
              blurRadius: 18,
              offset: const Offset(0, 6))
        ],
      ),
      child: Row(
        children: [
          // Score circle
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$score',
                style: const TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'HEALTH SCORE',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white70,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _label,
                  style: const TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                // Score bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(50),
                  child: LinearProgressIndicator(
                    value: score / 100.0,
                    minHeight: 6,
                    backgroundColor: Colors.white.withValues(alpha: 0.28),
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Colors.white),
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

// ─────────────────────────────────────────────────────────────
// COUNT CARD — cough / sneeze / snore
// ─────────────────────────────────────────────────────────────

class _CountCard extends StatelessWidget {
  final String icon;
  final String label;
  final int count;
  final Color accentColor;

  const _CountCard({
    required this.icon,
    required this.label,
    required this.count,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
              color: AppColors.shadow,
              blurRadius: 8,
              offset: Offset(0, 3))
        ],
      ),
      child: Column(
        children: [
          Text(icon, style: const TextStyle(fontSize: 24)),
          const SizedBox(height: 8),
          Text(
            '$count',
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: accentColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Nunito',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// WEEKLY BAR CHART
// ─────────────────────────────────────────────────────────────

class _WeeklyBarChart extends StatelessWidget {
  final List<DayBar> bars;

  const _WeeklyBarChart({required this.bars});

  @override
  Widget build(BuildContext context) {
    const maxHeight = 60.0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: bars.map((b) {
        final fill    = b.fill;
        final label   = b.label;
        final hasData = b.hasData;
        final barH    = hasData ? (fill * maxHeight).clamp(6.0, maxHeight) : 4.0;
        final isToday = bars.indexOf(b) == bars.length - 1;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              width: 26,
              height: barH,
              decoration: BoxDecoration(
                color: hasData
                    ? (isToday
                        ? AppColors.primary
                        : AppColors.primaryMid.withValues(alpha: 0.6))
                    : AppColors.divider,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 12,
                fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                color: isToday ? AppColors.primary : AppColors.textMuted,
              ),
            ),
          ],
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// WEEK STAT (avg score / total coughs etc.)
// ─────────────────────────────────────────────────────────────

class _WeekStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _WeekStat(
      {required this.label,
      required this.value,
      required this.icon,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'Nunito',
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Nunito',
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: AppColors.textMuted,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// INSIGHT CARD
// ─────────────────────────────────────────────────────────────

class _InsightCard extends StatelessWidget {
  final InsightMessage msg;
  const _InsightCard({required this.msg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryLight.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(msg.emoji, style: const TextStyle(fontSize: 26)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  msg.title,
                  style: const TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  msg.body,
                  style: const TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 13,
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

// ─────────────────────────────────────────────────────────────
// EMPTY STATE CARD
// ─────────────────────────────────────────────────────────────

class _EmptyStateCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyStateCard(
      {required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider, width: 1.2),
      ),
      child: Column(
        children: [
          Icon(icon, size: 40, color: AppColors.primaryMid),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'Nunito',
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Nunito',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
