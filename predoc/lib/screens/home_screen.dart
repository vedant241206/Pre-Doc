import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/storage_service.dart';
import '../services/dashboard_service.dart';
import '../services/notification_service.dart';
import '../services/insight_service.dart';
import '../services/passive_monitoring_service.dart';
import '../services/continuous_audio_service.dart';
import '../app_services.dart';
import 'your_tree_screen.dart';
import 'ask_ai_screen.dart';
import 'med_checkup_screen.dart';
import 'nearby_docs_screen.dart';
import 'settings_screen.dart';
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

  // ── Day 8: Passive monitoring ──
  PassiveMonitoringData? _passive;
  bool _passiveLoading = false;

  // ── Day 8: Live monitoring ──
  // Use module-level singletons so HomeScreen and SettingsScreen
  // share the SAME service instance (same mic stream, same event bus).
  final ContinuousAudioService _continuousAudio = appContinuousAudio;

  bool _liveMonitoringOn = false;
  int  _liveCough        = 0;
  int  _liveSneeze       = 0;
  int  _liveSnore        = 0;

  // Live probability values for pulse indicator
  double _liveCoughProb  = 0.0;
  double _liveSneezeProb = 0.0;
  double _liveSnoreProb  = 0.0;

  StreamSubscription<LiveDetectionEvent>?  _eventSub;
  StreamSubscription<Map<String, double>>? _probSub;

  static const _dashboard   = DashboardService();
  static const _passiveSvc  = PassiveMonitoringService();

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
    _initLiveMonitoring();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService.maybeShowDailyBanner(context, _today);
      _refreshPassive();
    });
  }

  void _initLiveMonitoring() {
    _liveMonitoringOn = StorageService.liveMonitoringEnabled;
    // Load persisted daily counts
    final counts = StorageService.getDailyLiveCounts();
    _liveCough  = counts['cough']  ?? 0;
    _liveSneeze = counts['sneeze'] ?? 0;
    _liveSnore  = counts['snore']  ?? 0;

    if (_liveMonitoringOn) {
      _subscribeToStreams();
    }
  }

  void _subscribeToStreams() {
    _eventSub = _continuousAudio.eventStream.listen((event) {
      if (!mounted) return;
      setState(() {
        switch (event.eventType) {
          case 'cough':  _liveCough++;  break;
          case 'sneeze': _liveSneeze++; break;
          case 'snore':  _liveSnore++;  break;
        }
      });
    });

    _probSub = _continuousAudio.probStream.listen((probs) {
      if (!mounted) return;
      setState(() {
        _liveCoughProb  = probs['cough']  ?? 0.0;
        _liveSneezeProb = probs['sneeze'] ?? 0.0;
        _liveSnoreProb  = probs['snore']  ?? 0.0;
      });
    });
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _probSub?.cancel();
    super.dispose();
  }

  /// Synchronous — SessionResult data is already loaded in SharedPreferences.
  void _loadDashboard() {
    // Use cached passive data (synchronous, already saved)
    _passive = StorageService.getPassiveDataToday();
    final sessions = StorageService.getSessions();
    _today    = _dashboard.computeToday(sessions, passive: _passive);
    _weekly   = _dashboard.computeWeekly(sessions);
    _insights = _dashboard.computeInsights(_today, passive: _passive);
  }

  /// Async passive monitoring refresh — runs native channel calls.
  /// Called once per app open (not continuously).
  Future<void> _refreshPassive() async {
    if (_passiveLoading) return;
    if (mounted) setState(() => _passiveLoading = true);
    try {
      final data = await _passiveSvc.refresh();
      await StorageService.savePassiveData(data);
      if (mounted) {
        setState(() {
          _passive = data;
          // Recompute dashboard with fresh passive data
          final sessions = StorageService.getSessions();
          _today    = _dashboard.computeToday(sessions, passive: data);
          _insights = _dashboard.computeInsights(_today, passive: data);
          _passiveLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _passiveLoading = false);
    }
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
        await _refreshPassive();
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _buildHeader()),
          SliverToBoxAdapter(child: _buildTodaySection()),
          SliverToBoxAdapter(child: _buildWeeklySection()),
          SliverToBoxAdapter(child: _buildInsightsSection()),
          // Day 8: Behaviour Insights section
          SliverToBoxAdapter(child: _buildBehaviorInsightsSection()),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
              Row(
                children: [
                  // Settings icon
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const SettingsScreen()),
                    ).then((_) => setState(() {
                      // Refresh live-monitoring state after returning
                      final wasOn = _liveMonitoringOn;
                      _liveMonitoringOn =
                          StorageService.liveMonitoringEnabled;
                      if (_liveMonitoringOn && !wasOn) {
                        _subscribeToStreams();
                      } else if (!_liveMonitoringOn && wasOn) {
                        _eventSub?.cancel();
                        _probSub?.cancel();
                      }
                    })),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.settings_rounded,
                          color: AppColors.textMuted, size: 20),
                    ),
                  ),
                  const SizedBox(width: 10),
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
            ],
          ),
          // ── Live Monitoring Banner ─────────────────────────────
          if (_liveMonitoringOn) ...[
            const SizedBox(height: 12),
            _LiveMonitoringBanner(
              cough:      _liveCough,
              sneeze:     _liveSneeze,
              snore:      _liveSnore,
              coughProb:  _liveCoughProb,
              sneezeProb: _liveSneezeProb,
              snoreProb:  _liveSnoreProb,
              onStop: () async {
                await _continuousAudio.stop();
                await StorageService.setLiveMonitoringEnabled(false);
                _eventSub?.cancel();
                _probSub?.cancel();
                if (mounted) setState(() => _liveMonitoringOn = false);
              },
            ),
          ],
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

          if (!_today.hasData && !_liveMonitoringOn) ...[
            _EmptyStateCard(
              icon: Icons.health_and_safety_outlined,
              title: 'No data yet',
              subtitle: 'Complete your device test or enable Live Monitoring to see your health score.',
            ),
          ] else ...[
            // Health score card (big, coloured)
            Builder(
              builder: (context) {
                int displayScore = _today.score;
                HealthColor displayColor = _today.color;

                if (_liveMonitoringOn || _liveCough > 0 || _liveSneeze > 0 || _liveSnore > 0) {
                  // Compute combined score including live events and passive sensor penalties
                  final insight = const InsightService().computeCombined(
                    liveCoughCount: _today.coughCount + _liveCough,
                    liveSneezeCount: _today.sneezeCount + _liveSneeze,
                    liveSnoreCount: _today.snoreCount + _liveSnore,
                    nightUsageRisk: _passive?.sleepRisk ?? false,
                    screenTimeRisk: _passive?.screenRisk ?? false,
                    lowActivity: _passive?.sedentary ?? false,
                  );
                  displayScore = insight.score;
                  displayColor = insight.color;
                }

                return _HealthScoreCard(score: displayScore, color: displayColor);
              },
            ),
            const SizedBox(height: 14),
            // Cough / Sneeze / Snore count row
            // Live monitoring counts stack on top of session counts
            Row(
              children: [
                Expanded(
                    child: _CountCard(
                  icon: '🤧',
                  label: 'COUGH',
                  count: _today.coughCount + _liveCough,
                  accentColor: const Color(0xFFEF4444),
                  isLive: _liveMonitoringOn,
                )),
                const SizedBox(width: 10),
                Expanded(
                    child: _CountCard(
                  icon: '🤲',
                  label: 'SNEEZE',
                  count: _today.sneezeCount + _liveSneeze,
                  accentColor: const Color(0xFFF59E0B),
                  isLive: _liveMonitoringOn,
                )),
                const SizedBox(width: 10),
                Expanded(
                    child: _CountCard(
                  icon: '😴',
                  label: 'SNORE',
                  count: _today.snoreCount + _liveSnore,
                  accentColor: const Color(0xFF8B5CF6),
                  isLive: _liveMonitoringOn,
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
  // BEHAVIOR INSIGHTS SECTION (Day 8)
  // ─────────────────────────────────────────────────────────────

  Widget _buildBehaviorInsightsSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ───────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Behavior Insights',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textDark,
                ),
              ),
              if (_passiveLoading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                )
              else
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: (_passive?.usageStatsAvailable ?? false)
                        ? AppColors.primaryLight
                        : const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(50),
                  ),
                  child: Text(
                    (_passive?.usageStatsAvailable ?? false)
                        ? 'Live'
                        : 'Enable Stats',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: (_passive?.usageStatsAvailable ?? false)
                          ? AppColors.primary
                          : const Color(0xFFB45309),
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 14),

          // ── No permission fallback ────────────────────────────
          if (!(_passive?.usageStatsAvailable ?? false) && !_passiveLoading)
            GestureDetector(
              onTap: () async {
                await _passiveSvc.openUsageSettings();
                await _refreshPassive();
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: const Color(0xFFFDE68A),
                    width: 1.5,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: AppColors.shadow,
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.bar_chart_rounded,
                      color: Color(0xFFB45309),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Usage Stats not enabled',
                          style: TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textDark,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Enable Usage Access in Settings to see screen time and sleep data.',
                          style: TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: 12,
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
            ),
          ),

          // ── Three stat cards ──────────────────────────────────
          if (_passive != null && (_passive!.usageStatsAvailable || _passive!.activityLevel != ActivityLevel.medium)) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                // Screen Time
                Expanded(
                  child: _BehaviorCard(
                    emoji: '📱',
                    label: 'SCREEN TIME',
                    value: _passive!.screenTimeLabel,
                    risk: _passive!.screenRisk,
                    accentColor: _passive!.screenRisk
                        ? const Color(0xFFEF4444)
                        : const Color(0xFF6366F1),
                  ),
                ),
                const SizedBox(width: 10),
                // Sleep Quality
                Expanded(
                  child: _BehaviorCard(
                    emoji: '🌙',
                    label: 'SLEEP',
                    value: _passive!.sleepQualityLabel,
                    risk: _passive!.sleepRisk,
                    accentColor: _passive!.sleepRisk
                        ? const Color(0xFFEF4444)
                        : const Color(0xFF8B5CF6),
                  ),
                ),
                const SizedBox(width: 10),
                // Activity Level
                Expanded(
                  child: _BehaviorCard(
                    emoji: '🏃',
                    label: 'ACTIVITY',
                    value: _passive!.activityLabel,
                    risk: _passive!.sedentary,
                    accentColor: _passive!.sedentary
                        ? const Color(0xFFEF4444)
                        : const Color(0xFF10B981),
                  ),
                ),
              ],
            ),
          ],

          // ── Pattern alert (late-night streak) ────────────────
          if (_passive?.lateNightPattern ?? false) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF1F2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFFFECACA),
                  width: 1.5,
                ),
              ),
              child: const Row(
                children: [
                  Text('🌙', style: TextStyle(fontSize: 22)),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Late-night usage pattern detected',
                          style: TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF9F1239),
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'High phone usage after 10 PM for 3+ consecutive nights.',
                          style: TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFBE123C),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ── Eye strain alert ──────────────────────────────────
          if (_passive?.eyeStrain ?? false) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFFFDE68A),
                  width: 1.5,
                ),
              ),
              child: const Row(
                children: [
                  Text('👁️', style: TextStyle(fontSize: 22)),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Eye strain risk',
                          style: TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF92400E),
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Screen use detected in low light. Increase brightness or rest your eyes.',
                          style: TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFB45309),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
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
  final bool  isLive;

  const _CountCard({
    required this.icon,
    required this.label,
    required this.count,
    required this.accentColor,
    this.isLive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: isLive
            ? Border.all(
                color: accentColor.withValues(alpha: 0.35), width: 1.5)
            : null,
        boxShadow: const [
          BoxShadow(
              color: AppColors.shadow,
              blurRadius: 8,
              offset: Offset(0, 3))
        ],
      ),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Text(icon, style: const TextStyle(fontSize: 24)),
              if (isLive)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: accentColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
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
          if (isLive)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'LIVE',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                  color: accentColor,
                  letterSpacing: 1,
                ),
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

// ─────────────────────────────────────────────────────────────
// BEHAVIOR CARD — screen time / sleep / activity (Day 8)
// ─────────────────────────────────────────────────────────────

class _BehaviorCard extends StatelessWidget {
  final String emoji;
  final String label;
  final String value;
  final bool   risk;
  final Color  accentColor;

  const _BehaviorCard({
    required this.emoji,
    required this.label,
    required this.value,
    required this.risk,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: risk
              ? const Color(0xFFFCA5A5).withValues(alpha: 0.6)
              : AppColors.divider,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: risk
                ? const Color(0xFFEF4444).withValues(alpha: 0.08)
                : AppColors.shadow,
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 26)),
              if (risk)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: Color(0xFFEF4444),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: accentColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Nunito',
              fontSize: 9,
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
// LIVE MONITORING BANNER (Day 8)
// Shows at the top of the home tab when ContinuousAudioService
// is running. Displays real-time prob bars + event counters.
// ─────────────────────────────────────────────────────────────

class _LiveMonitoringBanner extends StatelessWidget {
  final int    cough;
  final int    sneeze;
  final int    snore;
  final double coughProb;
  final double sneezeProb;
  final double snoreProb;
  final VoidCallback onStop;

  const _LiveMonitoringBanner({
    required this.cough,
    required this.sneeze,
    required this.snore,
    required this.coughProb,
    required this.sneezeProb,
    required this.snoreProb,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E3A5F), Color(0xFF2D5A8E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1E3A5F).withValues(alpha: 0.35),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  // Pulsing mic icon
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.mic_rounded,
                        color: Colors.white, size: 16),
                  ),
                  const SizedBox(width: 10),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Live Monitoring: ON',
                        style: TextStyle(
                          fontFamily: 'Nunito',
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'Detecting health signals in real-time',
                        style: TextStyle(
                          fontFamily: 'Nunito',
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Colors.white60,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              // Stop button
              GestureDetector(
                onTap: onStop,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: const Text(
                    'Stop',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // ── Real-time counters row ──
          Row(
            children: [
              _LiveCount(label: 'Coughs',  count: cough,
                  color: const Color(0xFFFF6B6B)),
              const SizedBox(width: 10),
              _LiveCount(label: 'Sneezes', count: sneeze,
                  color: const Color(0xFFFFD93D)),
              const SizedBox(width: 10),
              _LiveCount(label: 'Snores',  count: snore,
                  color: const Color(0xFFA78BFA)),
            ],
          ),

          const SizedBox(height: 12),

          // ── Probability bars ──
          _ProbBar(label: 'Cough',  value: coughProb,
              color: const Color(0xFFFF6B6B)),
          const SizedBox(height: 6),
          _ProbBar(label: 'Sneeze', value: sneezeProb,
              color: const Color(0xFFFFD93D)),
          const SizedBox(height: 6),
          _ProbBar(label: 'Snore',  value: snoreProb,
              color: const Color(0xFFA78BFA)),
        ],
      ),
    );
  }
}

// ── Live counter chip ─────────────────────────────────────────

class _LiveCount extends StatelessWidget {
  final String label;
  final int    count;
  final Color  color;

  const _LiveCount({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              '$count',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: color.withValues(alpha: 0.85),
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Real-time probability bar ─────────────────────────────────

class _ProbBar extends StatelessWidget {
  final String label;
  final double value;   // 0.0–1.0
  final Color  color;

  const _ProbBar({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final pct = (value * 100).toStringAsFixed(0);
    return Row(
      children: [
        SizedBox(
          width: 46,
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'Nunito',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Colors.white70,
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(50),
            child: LinearProgressIndicator(
              value: value.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: Colors.white.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 30,
          child: Text(
            '$pct%',
            textAlign: TextAlign.end,
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}
