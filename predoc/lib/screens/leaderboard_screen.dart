// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../utils/local_storage.dart';
import '../services/storage_service.dart';
import '../services/insight_service.dart';
import '../services/firebase_service.dart';

// ─────────────────────────────────────────────────────────────
// LEADERBOARD MODEL
// ─────────────────────────────────────────────────────────────

class LeaderboardUser {
  final String id;
  final String name;
  final int totalScore;
  final int streak;
  final int todayScore;
  final String country;
  final String city;
  final String subtitle;
  final bool isCurrentUser;

  const LeaderboardUser({
    required this.id,
    required this.name,
    required this.totalScore,
    required this.streak,
    required this.todayScore,
    required this.country,
    required this.city,
    this.subtitle = '',
    this.isCurrentUser = false,
  });
}

// ─────────────────────────────────────────────────────────────
// LEADERBOARD SCREEN
// ─────────────────────────────────────────────────────────────

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  List<LeaderboardUser> _allUsers = [];
  int _myRank = 0;

  static const _insightSvc = InsightService();

  // Colors based on UI image
  static const bgColor = Color(0xFFFCF5FC);
  static const purpleTheme = Color(0xFF6B48AC);
  static const darkText = Color(0xFF2A1B38);
  static const tabBg = Color(0xFFF3E5F5);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _init();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final sessions = StorageService.getSessions();
    final currentName =
        LocalStorage.userName.isNotEmpty ? LocalStorage.userName : 'You';
    final currentCountry =
        LocalStorage.country.isNotEmpty ? LocalStorage.country : '';
    final currentCity = LocalStorage.city.isNotEmpty ? LocalStorage.city : '';

    // Compute real total score from all sessions starting from base
    int myTotalScore = LocalStorage.baseScore;
    int myStreak = LocalStorage.baseStreak;
    int myTodayScore = 0;

    if (sessions.isNotEmpty) {
      // Today's score
      final todayKey =
          '${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}';
      for (final s in sessions) {
        final ins = _insightSvc.compute(
          coughCount: s.coughCount,
          sneezeCount: s.sneezeCount,
          snoreCount: s.snoreCount,
          faceDetected: s.faceDetected,
          brightness: s.brightnessValue,
        );
        myTotalScore += ins.score;
        if (s.sessionStart.startsWith(todayKey)) myTodayScore = ins.score;
      }

      // Streak computation
      final Map<String, int> bestDay = {};
      for (final s in sessions) {
        try {
          final dt = DateTime.parse(s.sessionStart);
          final key = '${dt.year}-${dt.month}-${dt.day}';
          final ins = _insightSvc.compute(
            coughCount: s.coughCount,
            sneezeCount: s.sneezeCount,
            snoreCount: s.snoreCount,
            faceDetected: s.faceDetected,
            brightness: s.brightnessValue,
          );
          if ((bestDay[key] ?? 0) < ins.score) bestDay[key] = ins.score;
        } catch (_) {}
      }
      final now = DateTime.now();
      int localStreak = 0;
      for (int i = 0; i < 365; i++) {
        final d = now.subtract(Duration(days: i));
        final key = '${d.year}-${d.month}-${d.day}';
        if ((bestDay[key] ?? 0) >= 60) {
          localStreak++;
        } else {
          break;
        }
      }
      myStreak += localStreak;
    }

    final me = LeaderboardUser(
      id: FirebaseService.currentUid ?? 'me',
      name: currentName,
      totalScore: myTotalScore,
      streak: myStreak,
      todayScore: myTodayScore,
      country: currentCountry,
      city: currentCity,
      subtitle: myStreak > 0
          ? 'STREAK: $myStreak day${myStreak == 1 ? '' : 's'}'
          : '',
      isCurrentUser: true,
    );

    List<LeaderboardUser> fetchedUsers = [];
    final data = await FirebaseService.getLeaderboard();
    for (final doc in data) {
      final uid = doc['uid'] ?? '';
      final name = doc['name'] ?? 'Anonymous';
      final score = doc['score'] ?? 0;
      final streak = doc['streak'] ?? 0;
      final today = doc['todayScore'] ?? 0;

      String country = doc['country'] ?? '';
      String city = doc['city'] ?? '';

      // DYNAMIC POPULATION:
      // Ensure the UI looks alive by distributing some mock users into the user's local region.
      if (uid.startsWith('mock_')) {
        final hash = name.codeUnits.fold(0, (a, b) => a + b);
        if (hash % 2 == 0 && currentCountry.isNotEmpty) {
          country = currentCountry;
        }
        if (hash % 3 == 0 && currentCity.isNotEmpty) {
          city = currentCity;
        }
      }

      final isMe = uid == me.id;

      fetchedUsers.add(LeaderboardUser(
        id: uid,
        name: name,
        totalScore: score,
        streak: streak,
        todayScore: today,
        country: country,
        city: city,
        subtitle:
            streak > 0 ? 'STREAK: $streak day${streak == 1 ? '' : 's'}' : '',
        isCurrentUser: isMe,
      ));
    }

    // Ensure the current user is always in the list (even if offline or not synced yet)
    if (!fetchedUsers.any((u) => u.isCurrentUser)) {
      fetchedUsers.add(me);
    } else {
      // If found, update the 'me' reference so local changes are immediately visible
      // (or let the DB version override). Let's use local for 'me' to ensure it's up to date.
      fetchedUsers.removeWhere((u) => u.isCurrentUser);
      fetchedUsers.add(me);
    }

    // Sort globally
    fetchedUsers.sort((a, b) => b.totalScore.compareTo(a.totalScore));

    int myPos = fetchedUsers.indexWhere((u) => u.isCurrentUser) + 1;

    setState(() {
      _isLoading = false;
      _allUsers = fetchedUsers;
      _myRank = myPos;
    });
  }

  String get _myCountry => LocalStorage.country;
  String get _myCity => LocalStorage.city;

  List<LeaderboardUser> get _globalList => _allUsers;
  List<LeaderboardUser> get _countryList => _allUsers
      .where((u) => u.country == _myCountry || u.isCurrentUser)
      .toList()
    ..sort((a, b) => b.totalScore.compareTo(a.totalScore));
  List<LeaderboardUser> get _cityList =>
      _allUsers.where((u) => u.city == _myCity || u.isCurrentUser).toList()
        ..sort((a, b) => b.totalScore.compareTo(a.totalScore));

  /// Format score with comma separator: 1540 → "1,540"
  String _formatScore(int score) {
    final s = score.toString();
    if (s.length <= 3) return s;
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    if (LocalStorage.skipAuth) {
      return Scaffold(
        backgroundColor: bgColor,
        body: SafeArea(
          child: Column(
            children: [
              _buildAppBar(),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.lock_rounded,
                            size: 72,
                            color: purpleTheme.withValues(alpha: 0.8)),
                        SizedBox(height: 24),
                        Text(
                          'Guest Profile',
                          style: TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            color: darkText,
                          ),
                        ),
                        SizedBox(height: 12),
                        Text(
                          'You need to make an account to use the leaderboard and save your progress in the cloud.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: darkText.withValues(alpha: 0.7),
                            height: 1.4,
                          ),
                        ),
                        SizedBox(height: 32),
                        ElevatedButton(
                          onPressed: () => context.push('/settings'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: purpleTheme,
                            elevation: 4,
                            shadowColor: purpleTheme.withValues(alpha: 0.5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(50),
                            ),
                            padding: EdgeInsets.symmetric(
                                horizontal: 28, vertical: 14),
                          ),
                          child: Text(
                            'Link Account in Settings',
                            style: TextStyle(
                              fontFamily: 'Nunito',
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              _buildBottomNav(),
            ],
          ),
        ),
      );
    }

    if (_isLoading) {
      return Scaffold(
          backgroundColor: bgColor,
          body: Center(child: CircularProgressIndicator(color: purpleTheme)));
    }

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(),
            _buildTabBar(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildTabContent(_globalList),
                  _buildTabContent(_countryList),
                  _buildTabContent(_cityList),
                ],
              ),
            ),
            _buildYouBanner(),
            _buildBottomNav(),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // APP BAR
  // ─────────────────────────────────────────────────────────────
  Widget _buildAppBar() {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => context.pop(),
                child: Icon(Icons.contact_page_rounded,
                    color: purpleTheme, size: 28),
              ),
              SizedBox(width: 8),
              Text(
                'Predoc',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: purpleTheme,
                ),
              ),
            ],
          ),
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: Color(0xFF336699),
              shape: BoxShape.circle,
              image: DecorationImage(
                image: AssetImage(
                    'assets/images/user_avatar.png'), // Will fail gracefully to icon if missing
                fit: BoxFit.cover,
              ),
            ),
            child: Icon(Icons.person, color: Colors.white70), // Fallback
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // TAB BAR
  // ─────────────────────────────────────────────────────────────
  Widget _buildTabBar() {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      height: 48,
      decoration: BoxDecoration(
        color: tabBg,
        borderRadius: BorderRadius.circular(50),
      ),
      child: TabBar(
        controller: _tabController,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: purpleTheme,
          borderRadius: BorderRadius.circular(50),
        ),
        labelStyle: TextStyle(
            fontFamily: 'Nunito', fontSize: 15, fontWeight: FontWeight.w700),
        labelColor: Colors.white,
        unselectedLabelColor: Color(0xFF8C7B9E),
        dividerColor: Colors.transparent,
        splashBorderRadius: BorderRadius.circular(50),
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        tabs: [
          Tab(text: 'Global'),
          Tab(text: 'Country'),
          Tab(text: 'City'),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // LIST CONTENT (Podium + Rows)
  // ─────────────────────────────────────────────────────────────
  Widget _buildTabContent(List<LeaderboardUser> list) {
    if (list.isEmpty) {
      return const Center(child: Text('No users found.'));
    }

    final top3 = list.take(3).toList();
    final rest = list.skip(3).toList();

    return ListView(
      padding: EdgeInsets.only(top: 10, bottom: 20),
      children: [
        if (top3.isNotEmpty) _buildPodium(top3),
        SizedBox(height: 16),
        ...rest.asMap().entries.map((e) => _buildRow(e.value, e.key + 4)),
        SizedBox(height: 16),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  // PODIUM (Top 3)
  // ─────────────────────────────────────────────────────────────
  Widget _buildPodium(List<LeaderboardUser> top3) {
    final u1 = top3.isNotEmpty ? top3[0] : null;
    final u2 = top3.length > 1 ? top3[1] : null;
    final u3 = top3.length > 2 ? top3[2] : null;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (u2 != null)
            Expanded(
                child: _buildPodiumItem(
                    u2, 2, Color(0xFFBDB3D1), Color(0xFFDED8E8), 100)),
          if (u1 != null)
            Expanded(
                child: Padding(
              padding: EdgeInsets.only(bottom: 20),
              child: _buildPodiumItem(
                  u1, 1, Color(0xFFFFCC00), Color(0xFFFFCC00), 126),
            )),
          if (u3 != null)
            Expanded(
                child: _buildPodiumItem(
                    u3, 3, Color(0xFFE89A4B), Color(0xFFF2A65A), 100)),
        ],
      ),
    );
  }

  Widget _buildPodiumItem(LeaderboardUser user, int rank, Color borderColor,
      Color pillColor, double size) {
    final is1st = rank == 1;
    final rankSuffix = is1st
        ? '1st'
        : rank == 2
            ? '2nd'
            : '3rd';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          alignment: Alignment.topCenter,
          clipBehavior: Clip.none,
          children: [
            // Dark circle
            Container(
              width: size,
              height: size,
              margin: EdgeInsets.only(top: is1st ? 14 : 0),
              decoration: BoxDecoration(
                color: Color(0xFF0F1A24),
                shape: BoxShape.circle,
                border: Border.all(color: borderColor, width: is1st ? 5 : 4),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (is1st)
                      Text('RANK',
                          style: TextStyle(
                              fontFamily: 'Nunito',
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF00BFFF))),
                    // Drop shadow effect for rank number
                    Text(
                      '$rank',
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: is1st ? 46 : 38,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF33C2FF),
                        height: 1.0,
                        shadows: [
                          Shadow(
                              color: Colors.cyanAccent.withValues(alpha: 0.5),
                              blurRadius: 10)
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Sub-pill (1st/2nd/3rd)
            Positioned(
              bottom: -10,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: pillColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  rankSuffix,
                  style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: darkText),
                ),
              ),
            ),
            // Top star for 1st
            if (is1st)
              Positioned(
                top: 0,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                      color: pillColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: bgColor, width: 2)),
                  child:
                      Icon(Icons.star_rounded, color: Colors.white, size: 18),
                ),
              ),
          ],
        ),
        SizedBox(height: 20),
        Text(
          user.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: darkText),
        ),
        SizedBox(height: 2),
        Text(
          '${user.totalScore} pts',
          style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: purpleTheme),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  // LIST ROW (Ranks 4+)
  // ─────────────────────────────────────────────────────────────
  Widget _buildRow(LeaderboardUser user, int rank) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      padding: EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(50),
        boxShadow: [
          BoxShadow(
              color: Color(0xFFEBE0EE), blurRadius: 12, offset: Offset(0, 4))
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(
              '$rank',
              style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF887A9A)),
            ),
          ),
          SizedBox(width: 14),
          // Avatar circle
          Container(
            width: 44,
            height: 44,
            decoration:
                BoxDecoration(color: Color(0xFF0F1A24), shape: BoxShape.circle),
            child: Center(
              child: Text(
                user.name[0],
                style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Colors.cyan),
              ),
            ),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.name,
                  style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: darkText),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (user.subtitle.isNotEmpty)
                  Text(
                    user.subtitle,
                    style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF9081A4),
                        letterSpacing: 0.5),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatScore(user.totalScore),
                style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: purpleTheme),
              ),
              Text(
                'PTS',
                style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF9081A4)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // STICKY "YOU" BANNER
  // ─────────────────────────────────────────────────────────────
  Widget _buildYouBanner() {
    final me = _allUsers.firstWhere((u) => u.isCurrentUser);

    return Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: BoxDecoration(
        color: purpleTheme,
        borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24), topRight: Radius.circular(24)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Profile image with YOU badge
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  image: DecorationImage(
                      image: AssetImage('assets/images/user_avatar.png'),
                      fit: BoxFit.cover),
                  color: Colors.black26, // Fallback
                ),
              ),
              Positioned(
                top: -6,
                right: -12,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      color: Color(0xFFFFCC00),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text('YOU',
                      style: TextStyle(
                          fontFamily: 'Nunito',
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: darkText)),
                ),
              ),
            ],
          ),
          SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  me.name,
                  style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.white),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'RANKED #${_myRank == 0 ? 142 : _myRank}',
                  style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFBA9EFA),
                      letterSpacing: 0.5),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatScore(me.totalScore),
                style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: Colors.white),
              ),
              Text(
                'POINTS',
                style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFBA9EFA),
                    letterSpacing: 0.5),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // FAKE BOTTOM NAV BAR (Matching Home Screen & Image)
  // ─────────────────────────────────────────────────────────────
  Widget _buildBottomNav() {
    return Container(
      height: 84,
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom > 0 ? 0 : 8),
      decoration: BoxDecoration(
        color: bgColor,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _navItem(
              Icons.home_rounded, 'HOME', false, () => context.go('/home')),
          _navItem(Icons.park_rounded, 'YOUR TREE', true, () => context.pop()),
          _navItem(Icons.smart_toy_rounded, 'ASK AI', false,
              () => context.go('/home')),
          _navItem(Icons.medical_services_rounded, 'MED CHECKUP', false,
              () => context.go('/home')),
          _navItem(Icons.location_on_rounded, 'NEARBY DOCS', false,
              () => context.go('/home')),
        ],
      ),
    );
  }

  Widget _navItem(
      IconData icon, String label, bool isActive, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isActive ? Color(0xFFBCA1EE) : Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: isActive ? 26 : 24,
                color: isActive ? Colors.white : Color(0xFF718096),
              ),
            ),
            SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: isActive ? purpleTheme : Color(0xFF718096),
                letterSpacing: 0.5,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.visible,
            ),
          ],
        ),
      ),
    );
  }
}
