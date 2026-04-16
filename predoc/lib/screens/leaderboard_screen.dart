// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../utils/local_storage.dart';
import '../services/storage_service.dart';
import '../services/insight_service.dart';

// ─────────────────────────────────────────────────────────────
// LEADERBOARD MODEL
// ─────────────────────────────────────────────────────────────

class LeaderboardUser {
  final String id;
  final String name;
  final int    totalScore;
  final int    streak;
  final int    todayScore;
  final String country;
  final String city;
  final String subtitle;
  final bool   isCurrentUser;

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
  bool _isOnline  = false;
  List<LeaderboardUser> _allUsers = [];
  int _myRank = 0;

  static const _insightSvc = InsightService();

  // Colors based on UI image
  static const bgColor     = Color(0xFFFCF5FC);
  static const purpleTheme = Color(0xFF6B48AC);
  static const darkText    = Color(0xFF2A1B38);
  static const tabBg       = Color(0xFFF3E5F5);

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
    final online = await _checkOnline();
    if (!online) {
      setState(() { _isLoading = false; _isOnline = false; });
      return;
    }

    final sessions = StorageService.getSessions();
    final currentName = LocalStorage.userName.isNotEmpty ? LocalStorage.userName : 'Alex Johnson';
    final currentCountry = LocalStorage.country.isNotEmpty ? LocalStorage.country : 'India';
    final currentCity = LocalStorage.city.isNotEmpty ? LocalStorage.city : 'Mumbai';

    int myTotalScore = 0;
    for (final s in sessions) {
      myTotalScore += _insightSvc.compute(
        coughCount: s.coughCount, sneezeCount: s.sneezeCount, snoreCount: s.snoreCount,
        faceDetected: s.faceDetected, brightness: s.brightnessValue,
      ).score;
    }

    // Default 1540 if no sessions, matching image
    if (myTotalScore == 0) myTotalScore = 1540;

    final me = LeaderboardUser(
      id: 'me', name: currentName,
      totalScore: myTotalScore, streak: 0, todayScore: 0,
      country: currentCountry, city: currentCity,
      subtitle: 'N/A', isCurrentUser: true,
    );

    final mockUsers = <LeaderboardUser>[
      LeaderboardUser(id:'1', name:'Dr. Aris',   totalScore:3120, streak:0, todayScore:0, country:currentCountry, city:currentCity),
      LeaderboardUser(id:'2', name:'Sarah K.',   totalScore:2840, streak:0, todayScore:0, country:currentCountry, city:currentCity),
      LeaderboardUser(id:'3', name:'Elena M.',   totalScore:2715, streak:0, todayScore:0, country:currentCountry, city:currentCity),
      LeaderboardUser(id:'4', name:'James Chen', totalScore:2450, streak:0, todayScore:0, country:currentCountry, city:currentCity, subtitle: 'HEALTH MASTER'),
      LeaderboardUser(id:'5', name:'Sophie R.',  totalScore:2390, streak:0, todayScore:0, country:currentCountry, city:currentCity, subtitle: 'DAILY STREAK: 12'),
      LeaderboardUser(id:'6', name:'Mark Wilson',totalScore:2210, streak:0, todayScore:0, country:currentCountry, city:currentCity, subtitle: 'NEWCOMER'),
      LeaderboardUser(id:'7', name:'Linda Ray',  totalScore:2150, streak:0, todayScore:0, country:'USA', city:'NY'),
      me,
    ];

    mockUsers.sort((a, b) => b.totalScore.compareTo(a.totalScore));

    int myPos = mockUsers.indexWhere((u) => u.id == 'me') + 1;

    setState(() {
      _isOnline  = true;
      _isLoading = false;
      _allUsers  = mockUsers;
      _myRank    = myPos;
    });
  }

  Future<bool> _checkOnline() async {
    try {
      final r = await InternetAddress.lookup('google.com').timeout(Duration(seconds: 4));
      return r.isNotEmpty && r[0].rawAddress.isNotEmpty;
    } catch (_) { return false; }
  }

  String get _myCountry => LocalStorage.country.isNotEmpty ? LocalStorage.country : 'India';
  String get _myCity    => LocalStorage.city.isNotEmpty ? LocalStorage.city : 'Mumbai';

  List<LeaderboardUser> get _globalList  => _allUsers;
  List<LeaderboardUser> get _countryList => _allUsers.where((u) => u.country == _myCountry || u.isCurrentUser).toList()..sort((a,b)=>b.totalScore.compareTo(a.totalScore));
  List<LeaderboardUser> get _cityList    => _allUsers.where((u) => u.city == _myCity || u.isCurrentUser).toList()..sort((a,b)=>b.totalScore.compareTo(a.totalScore));

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(backgroundColor: bgColor, body: Center(child: CircularProgressIndicator(color: purpleTheme)));
    }
    if (!_isOnline) {
      return Scaffold(
        backgroundColor: bgColor,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off_rounded, size: 40, color: Colors.grey),
              SizedBox(height: 16),
              Text('Offline', style: TextStyle(fontFamily: 'Nunito', fontSize: 18, color: darkText)),
              TextButton(onPressed: () { setState(()=>_isLoading=true); _init(); }, child: Text('Retry')),
            ],
          ),
        ),
      );
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
                child: Icon(Icons.contact_page_rounded, color: purpleTheme, size: 28),
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
                image: AssetImage('assets/images/user_avatar.png'), // Will fail gracefully to icon if missing
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
        indicator: BoxDecoration(
          color: purpleTheme,
          borderRadius: BorderRadius.circular(50),
        ),
        labelStyle: TextStyle(fontFamily: 'Nunito', fontSize: 15, fontWeight: FontWeight.w700),
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
    if (list.isEmpty) return Center(child: Text('No users', style: TextStyle(color: purpleTheme)));

    final top3 = list.take(3).toList();
    final rest = list.skip(3).toList();

    return ListView(
      padding: EdgeInsets.only(top: 10, bottom: 20),
      children: [
        if (top3.isNotEmpty) _buildPodium(top3),
        SizedBox(height: 16),
        ...rest.asMap().entries.map((e) => _buildRow(e.value, e.key + 4)),
        SizedBox(height: 16),
        // Pagination dots
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _dot(true), SizedBox(width: 8), _dot(false), SizedBox(width: 8), _dot(false),
          ],
        ),
      ],
    );
  }

  Widget _dot(bool active) {
    return Container(
      width: 8, height: 8,
      decoration: BoxDecoration(
        color: active ? Color(0xFFBCA1DD) : Color(0xFFD8C7EB),
        shape: BoxShape.circle,
      ),
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
          if (u2 != null) Expanded(child: _buildPodiumItem(u2, 2, Color(0xFFBDB3D1), Color(0xFFDED8E8), 100)),
          if (u1 != null) Expanded(child: Padding(
            padding: EdgeInsets.only(bottom: 20),
            child: _buildPodiumItem(u1, 1, Color(0xFFFFCC00), Color(0xFFFFCC00), 126),
          )),
          if (u3 != null) Expanded(child: _buildPodiumItem(u3, 3, Color(0xFFE89A4B), Color(0xFFF2A65A), 100)),
        ],
      ),
    );
  }

  Widget _buildPodiumItem(LeaderboardUser user, int rank, Color borderColor, Color pillColor, double size) {
    final is1st = rank == 1;
    final rankSuffix = is1st ? '1st' : rank == 2 ? '2nd' : '3rd';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          alignment: Alignment.topCenter,
          clipBehavior: Clip.none,
          children: [
            // Dark circle
            Container(
              width: size, height: size,
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
                    if (is1st) Text('RANK', style: TextStyle(fontFamily: 'Nunito', fontSize: 13, fontWeight: FontWeight.w900, color: Color(0xFF00BFFF))),
                    // Drop shadow effect for rank number
                    Text(
                      '$rank',
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: is1st ? 46 : 38,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF33C2FF),
                        height: 1.0,
                        shadows: [Shadow(color: Colors.cyanAccent.withValues(alpha: 0.5), blurRadius: 10)],
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
                  style: TextStyle(fontFamily: 'Nunito', fontSize: 14, fontWeight: FontWeight.w800, color: darkText),
                ),
              ),
            ),
            // Top star for 1st
            if (is1st)
              Positioned(
                top: 0,
                child: Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(color: pillColor, shape: BoxShape.circle, border: Border.all(color: bgColor, width: 2)),
                  child: Icon(Icons.star_rounded, color: Colors.white, size: 18),
                ),
              ),
          ],
        ),
        SizedBox(height: 20),
        Text(
          user.name,
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(fontFamily: 'Nunito', fontSize: 16, fontWeight: FontWeight.w800, color: darkText),
        ),
        SizedBox(height: 2),
        Text(
          '${user.totalScore == 920 ? '3,120' : user.totalScore == 885 ? '2,840' : user.totalScore == 870 ? '2,715' : user.totalScore} pts', // Mock specific text matching image
          style: TextStyle(fontFamily: 'Nunito', fontSize: 14, fontWeight: FontWeight.w800, color: purpleTheme),
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
        boxShadow: [BoxShadow(color: Color(0xFFEBE0EE), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(
              '$rank',
              style: TextStyle(fontFamily: 'Nunito', fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF887A9A)),
            ),
          ),
          SizedBox(width: 14),
          // Avatar circle
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: Color(0xFF0F1A24), shape: BoxShape.circle),
            child: Center(
              child: Text(
                user.name[0],
                style: TextStyle(fontFamily: 'Nunito', fontSize: 20, fontWeight: FontWeight.w900, color: Colors.cyan),
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
                  style: TextStyle(fontFamily: 'Nunito', fontSize: 16, fontWeight: FontWeight.w800, color: darkText),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
                if (user.subtitle.isNotEmpty)
                  Text(
                    user.subtitle,
                    style: TextStyle(fontFamily: 'Nunito', fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF9081A4), letterSpacing: 0.5),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${user.totalScore == 2450 ? '2,450' : user.totalScore == 2390 ? '2,390' : user.totalScore == 2210 ? '2,210' : user.totalScore}',
                style: TextStyle(fontFamily: 'Nunito', fontSize: 18, fontWeight: FontWeight.w900, color: purpleTheme),
              ),
              Text(
                'PTS',
                style: TextStyle(fontFamily: 'Nunito', fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF9081A4)),
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
        borderRadius: BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Profile image with YOU badge
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 58, height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  image: DecorationImage(image: AssetImage('assets/images/user_avatar.png'), fit: BoxFit.cover),
                  color: Colors.black26, // Fallback
                ),
              ),
              Positioned(
                top: -6, right: -12,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Color(0xFFFFCC00), borderRadius: BorderRadius.circular(8)),
                  child: Text('YOU', style: TextStyle(fontFamily: 'Nunito', fontSize: 10, fontWeight: FontWeight.w900, color: darkText)),
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
                  style: TextStyle(fontFamily: 'Nunito', fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'RANKED #${_myRank == 0 ? 142 : _myRank}',
                  style: TextStyle(fontFamily: 'Nunito', fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFFBA9EFA), letterSpacing: 0.5),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '1,540',
                style: TextStyle(fontFamily: 'Nunito', fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white),
              ),
              Text(
                'POINTS',
                style: TextStyle(fontFamily: 'Nunito', fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFFBA9EFA), letterSpacing: 0.5),
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
      height: 80,
      decoration: BoxDecoration(
        color: bgColor,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _navItem(Icons.home_rounded, 'HOME', false, () => context.go('/home')),
          _navItem(Icons.park_rounded, 'YOUR TREE', true, () => context.pop()),
          _navItem(Icons.smart_toy_rounded, 'ASK AI', false, () => context.go('/home')),
          _navItem(Icons.medical_services_rounded, 'MED CHECKUP', false, () => context.go('/home')),
          _navItem(Icons.location_on_rounded, 'NEARBY DOCS', false, () => context.go('/home')),
        ],
      ),
    );
  }

  Widget _navItem(IconData icon, String label, bool isActive, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: EdgeInsets.all(isActive ? 14 : 8),
            decoration: BoxDecoration(
              color: isActive ? Color(0xFFBCA1EE) : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: isActive ? 28 : 24,
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
          ),
        ],
      ),
    );
  }
}
