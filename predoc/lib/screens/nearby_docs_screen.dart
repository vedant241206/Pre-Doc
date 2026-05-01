// NearbyDocsScreen — Day 12 UI Refinement
// Logic/API/GPS unchanged. UI polished per Day 12 spec.

import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';

class _NearbyDoctor {
  final String placeId, name, vicinity, type;
  final double rating, lat, lng, distanceKm;
  final int userRatingsTotal;
  final bool openNow;
  const _NearbyDoctor({
    required this.placeId, required this.name, required this.vicinity,
    required this.type, required this.rating, required this.userRatingsTotal,
    required this.lat, required this.lng, required this.distanceKm,
    required this.openNow,
  });
}

class NearbyDocsScreen extends StatefulWidget {
  const NearbyDocsScreen({super.key});
  @override
  State<NearbyDocsScreen> createState() => _NearbyDocsScreenState();
}

class _NearbyDocsScreenState extends State<NearbyDocsScreen> {
  static List<_NearbyDoctor>? _cache;
  static double? _cacheLat, _cacheLng;

  List<_NearbyDoctor> _doctors = [];
  bool    _loading = false;
  String  _error   = '';
  double? _userLat, _userLng;
  String  _locationName = 'Finding location…';

  @override
  void initState() {
    super.initState();
    if (_cache != null) {
      _doctors = _cache!;
      _userLat = _cacheLat;
      _userLng = _cacheLng;
    }
  }

  Future<void> _fetchDoctors() async {
    setState(() { _loading = true; _error = ''; });
    try {
      final pos = await _getLocation();
      _userLat  = pos.latitude;
      _userLng  = pos.longitude;
      _fetchLocationName(pos.latitude, pos.longitude);
      final results = await _searchPlaces(pos.latitude, pos.longitude);
      _cache    = results;
      _cacheLat = _userLat;
      _cacheLng = _userLng;
      if (mounted) setState(() { _doctors = results; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<Position> _getLocation() async {
    final serviceOn = await Geolocator.isLocationServiceEnabled();
    if (!serviceOn) throw 'GPS is off. Please enable location services.';
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied) throw 'Location permission denied.';
    }
    if (perm == LocationPermission.deniedForever) {
      throw 'Location permanently denied.\nEnable it in device Settings → Apps → Predoc → Permissions.';
    }
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
    );
  }

  Future<void> _fetchLocationName(double lat, double lng) async {
    try {
      final url = Uri.parse(
          'https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lng&zoom=10&addressdetails=1');
      final resp = await http.get(url, headers: {'User-Agent': 'PredocApp/1.0'});
      if (resp.statusCode == 200) {
        final data    = jsonDecode(resp.body);
        final address = data['address'] as Map<String, dynamic>?;
        if (address != null) {
          final city = address['city'] ?? address['town'] ??
              address['county'] ?? address['state'];
          if (city != null && mounted) setState(() => _locationName = city.toString());
        }
      }
    } catch (_) {}
  }

  Future<List<_NearbyDoctor>> _searchPlaces(double lat, double lng) async {
    final url   = Uri.parse('https://overpass-api.de/api/interpreter');
    final query = '''
[out:json][timeout:15];
(
  node["amenity"="hospital"](around:10000,$lat,$lng);
  way["amenity"="hospital"](around:10000,$lat,$lng);
  node["amenity"="doctors"](around:10000,$lat,$lng);
  way["amenity"="doctors"](around:10000,$lat,$lng);
  node["amenity"="clinic"](around:10000,$lat,$lng);
  way["amenity"="clinic"](around:10000,$lat,$lng);
);
out center;
''';
    late http.Response resp;
    try {
      resp = await http.post(url,
          headers: {'Accept': '*/*', 'User-Agent': 'PredocApp/1.0'},
          body: {'data': query}).timeout(const Duration(seconds: 15));
    } catch (_) {
      throw 'No internet connection. Please connect and try again.';
    }
    if (resp.statusCode != 200) {
      if (resp.statusCode == 429) throw 'OSM server busy. Please wait a moment.';
      throw 'Server error ${resp.statusCode}. Try again.';
    }
    final json     = jsonDecode(resp.body) as Map<String, dynamic>;
    final elements = json['elements'] as List<dynamic>? ?? [];
    final results  = <_NearbyDoctor>[];

    for (final e in elements) {
      final tags  = e['tags'] as Map<String, dynamic>? ?? {};
      final eLat  = e['lat'] ?? e['center']?['lat'];
      final eLng  = e['lon'] ?? e['center']?['lon'];
      if (eLat == null || eLng == null) continue;

      final name = tags['name'] as String? ?? 'Medical Facility';
      final type = tags['amenity'] as String? ?? '';
      String typeLabel = '🏥 Healthcare';
      if (type == 'hospital') { typeLabel = '🏥 Hospital'; }
      else if (type == 'doctors') { typeLabel = '👨‍⚕️ Doctor'; }
      else if (type == 'clinic') { typeLabel = '🩺 Clinic'; }

      final street   = tags['addr:street'] as String? ?? '';
      final city     = tags['addr:city']   as String? ?? '';
      final vicinity = street.isNotEmpty
          ? '$street${city.isNotEmpty ? ', $city' : ''}'
          : city;

      results.add(_NearbyDoctor(
        placeId:         e['id'].toString(),
        name:            name,
        vicinity:        vicinity,
        type:            typeLabel,
        rating:          0.0,
        userRatingsTotal: 0,
        lat:             (eLat as num).toDouble(),
        lng:             (eLng as num).toDouble(),
        distanceKm:      _haversineKm(lat, lng, (eLat).toDouble(), (eLng).toDouble()),
        openNow:         false,
      ));
    }

    final seen   = <String>{};
    return results.where((d) => seen.add(d.placeId)).toList()
      ..sort((a, b) => a.distanceKm.compareTo(b.distanceKm))
      ..take(8);
  }

  double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
    const r   = 6371.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a    = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) *
            sin(dLon / 2) * sin(dLon / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  String _distLabel(double km) =>
      km < 1.0 ? '${(km * 1000).round()} m' : '${km.toStringAsFixed(1)} km';

  Future<void> _openNavigation(_NearbyDoctor doc) async {
    final geo = Uri.parse('geo:${doc.lat},${doc.lng}?q=${Uri.encodeComponent(doc.name)}');
    await launchUrl(geo, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _buildHeader(),
      Expanded(child: _buildBody()),
    ]);
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(
          AppColors.paddingH, 20, AppColors.paddingH, AppColors.paddingV),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(bottom: BorderSide(color: AppColors.divider)),
        boxShadow: [BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.05),
            blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Nearby Doctors', style: TextStyle(fontFamily: 'Nunito',
              fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.textDark)),
          const SizedBox(height: 2),
          Row(children: [
            const Icon(Icons.location_on_rounded, color: AppColors.primary, size: 14),
            const SizedBox(width: 4),
            Text(_locationName, style: const TextStyle(fontFamily: 'Nunito',
                fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
          ]),
        ])),
        if (_doctors.isNotEmpty && !_loading)
          IconButton(
            onPressed: () { _cache = null; _fetchDoctors(); },
            icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
          ),
      ]),
    );
  }

  Widget _buildBody() {
    if (_loading)           return _buildLoading();
    if (_error.isNotEmpty)  return _buildError();
    if (_doctors.isEmpty)   return _buildLanding();
    return _buildList();
  }

  Widget _buildLanding() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(children: [
        const SizedBox(height: 16),
        Container(
          width: 96, height: 96,
          decoration: const BoxDecoration(
              color: AppColors.primaryLight, shape: BoxShape.circle),
          child: const Icon(Icons.local_hospital_rounded,
              color: AppColors.primary, size: 50),
        ),
        const SizedBox(height: 20),
        const Text('Find Doctors Near You',
            style: TextStyle(fontFamily: 'Nunito', fontSize: 22,
                fontWeight: FontWeight.w900, color: AppColors.textDark)),
        const SizedBox(height: 8),
        const Text(
          'Predoc will use your GPS to find up to 8 doctors & hospitals '
          'sorted nearest to farthest. Tap GO on any result for navigation.',
          textAlign: TextAlign.center,
          style: TextStyle(fontFamily: 'Nunito', fontSize: 14,
              fontWeight: FontWeight.w600, color: AppColors.textMuted, height: 1.5),
        ),
        const SizedBox(height: 24),
        _infoChip(Icons.wifi_rounded,        'Requires internet'),
        const SizedBox(height: 10),
        _infoChip(Icons.location_on_rounded, 'Uses your GPS location'),
        const SizedBox(height: 10),
        _infoChip(Icons.savings_rounded,     'API called only when you tap'),
        const SizedBox(height: 28),

        _TapScaleButton(
          onTap: _fetchDoctors,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(AppColors.radiusCard),
                boxShadow: [BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: 12, offset: const Offset(0, 4))]),
            child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.search_rounded, color: Colors.white, size: 22),
              SizedBox(width: 10),
              Text('Find Doctors Near Me', style: TextStyle(fontFamily: 'Nunito',
                  fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          '⚡ Results are cached for your session — navigating away\nand back will NOT consume extra API credits.',
          textAlign: TextAlign.center,
          style: TextStyle(fontFamily: 'Nunito', fontSize: 11,
              fontWeight: FontWeight.w600, color: AppColors.textMuted, height: 1.5),
        ),
      ]),
    );
  }

  Widget _infoChip(IconData icon, String label) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
          color: AppColors.primaryLight,
          borderRadius: BorderRadius.circular(50)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: AppColors.primary),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontFamily: 'Nunito',
            fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primaryDark)),
      ]),
    ),
  );

  Widget _buildLoading() => const Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(width: 52, height: 52,
          child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 3)),
      SizedBox(height: 20),
      Text('Getting your location…', style: TextStyle(fontFamily: 'Nunito',
          fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textDark)),
      SizedBox(height: 6),
      Text('Then searching for doctors nearby', style: TextStyle(
          fontFamily: 'Nunito', fontSize: 12, fontWeight: FontWeight.w600,
          color: AppColors.textMuted)),
    ]),
  );

  Widget _buildError() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 72, height: 72,
          decoration: const BoxDecoration(
              color: Color(0xFFFEE2E2), shape: BoxShape.circle),
          child: const Icon(Icons.wifi_off_rounded,
              color: AppColors.risk, size: 36),
        ),
        const SizedBox(height: 16),
        Text(_error, textAlign: TextAlign.center,
            style: const TextStyle(fontFamily: 'Nunito', fontSize: 14,
                fontWeight: FontWeight.w700, color: AppColors.textDark, height: 1.5)),
        const SizedBox(height: 24),
        _TapScaleButton(
          onTap: _fetchDoctors,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
            decoration: BoxDecoration(color: AppColors.primary,
                borderRadius: BorderRadius.circular(50)),
            child: const Text('Try Again', style: TextStyle(fontFamily: 'Nunito',
                fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
          ),
        ),
      ]),
    ),
  );

  Widget _buildList() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
          AppColors.paddingH, AppColors.paddingV, AppColors.paddingH, 100),
      itemCount: _doctors.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) => _docCard(_doctors[i], i),
    );
  }

  Widget _docCard(_NearbyDoctor doc, int index) {
    const avatarColors = [
      Color(0xFFEDE9FE), Color(0xFFDCFCE7), Color(0xFFFEF3C7),
      Color(0xFFFFE4E6), Color(0xFFE0F2FE), Color(0xFFF0FDF4),
      Color(0xFFFFF7ED), Color(0xFFF5F3FF),
    ];
    const iconColors = [
      AppColors.primary, Color(0xFF16A34A), Color(0xFFB45309),
      Color(0xFFE11D48), Color(0xFF0284C7), Color(0xFF059669),
      Color(0xFFD97706), Color(0xFF7C3AED),
    ];
    final bg = avatarColors[index % avatarColors.length];
    final ic = iconColors[index % iconColors.length];

    return Container(
      padding: const EdgeInsets.all(AppColors.paddingV),
      decoration: appCardDecoration(),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        // Rank + icon
        Stack(clipBehavior: Clip.none, children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
                color: bg, borderRadius: BorderRadius.circular(AppColors.radiusCard)),
            child: Center(child: Icon(
              doc.type.contains('Hospital')
                  ? Icons.local_hospital_rounded
                  : Icons.medical_services_rounded,
              color: ic, size: 28)),
          ),
          Positioned(top: -6, left: -6, child: Container(
            width: 20, height: 20,
            decoration: const BoxDecoration(
                color: AppColors.primary, shape: BoxShape.circle),
            child: Center(child: Text('${index + 1}', style: const TextStyle(
                fontFamily: 'Nunito', fontSize: 10,
                fontWeight: FontWeight.w900, color: Colors.white))),
          )),
        ]),

        const SizedBox(width: 14),

        // Info
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(doc.name, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'Nunito', fontSize: 15,
                  fontWeight: FontWeight.w800, color: AppColors.textDark)),
          const SizedBox(height: 3),
          Row(children: [
            Text(doc.type, style: const TextStyle(fontFamily: 'Nunito',
                fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary)),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(8)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.near_me_rounded, size: 11, color: AppColors.primary),
                const SizedBox(width: 4),
                Text(_distLabel(doc.distanceKm), style: const TextStyle(
                    fontFamily: 'Nunito', fontSize: 11,
                    fontWeight: FontWeight.w800, color: AppColors.primary)),
              ]),
            ),
            if (doc.vicinity.isNotEmpty) ...[
              const SizedBox(width: 6),
              Flexible(child: Text(doc.vicinity, maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'Nunito', fontSize: 11,
                      fontWeight: FontWeight.w600, color: AppColors.textMuted))),
            ],
          ]),
        ])),

        const SizedBox(width: 10),

        // Navigate button
        _TapScaleButton(
          onTap: () => _openNavigation(doc),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(AppColors.radiusCard),
              boxShadow: [BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  blurRadius: 6, offset: const Offset(0, 3))],
            ),
            child: const Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.navigation_rounded, color: Colors.white, size: 18),
              SizedBox(height: 2),
              Text('GO', style: TextStyle(fontFamily: 'Nunito', fontSize: 11,
                  fontWeight: FontWeight.w900, color: Colors.white)),
            ]),
          ),
        ),
      ]),
    );
  }
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
