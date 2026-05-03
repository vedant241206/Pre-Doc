import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart';
import '../utils/local_storage.dart';
import 'storage_service.dart';
import 'insight_service.dart';

class FirebaseService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final GoogleSignIn _googleSignIn = GoogleSignIn();

  static const _insightSvc = InsightService();

  /// Sign in with Google and link to Firebase Auth.
  /// Flow:
  ///   • Returning user (Firestore doc exists) → restore full profile from cloud,
  ///     then let the router decide which onboarding steps still need to be done.
  ///   • New user (no doc yet) → save display name and mark logged in only.
  static Future<User?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null; // User cancelled

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential = await _auth.signInWithCredential(credential);
      final user = userCredential.user;

      if (user != null) {
        final doc = await _db.collection('users').doc(user.uid).get();

        if (doc.exists) {
          // ── Returning user: restore full profile from Firestore ──
          await _restoreProfileFromCloud(doc.data()!, user);
        } else {
          // ── Brand-new user: store display name only ──
          await LocalStorage.setUserName(user.displayName ?? '');
        }

        // Always mark auth as done after a successful sign-in.
        await LocalStorage.setLoggedIn();

        // Push any locally accumulated data back up.
        await syncUserData();
      }

      return user;
    } catch (e) {
      debugPrint('Google Sign-In Error: $e');
      debugPrint('Falling back to anonymous sign-in...');
      try {
        final UserCredential userCredential = await _auth.signInAnonymously();
        final user = userCredential.user;
        if (user != null) {
          await LocalStorage.setUserName('Anonymous User');
          await LocalStorage.setLoggedIn();
          await syncUserData();
        }
        return user;
      } catch (anonErr) {
        debugPrint('Anonymous Sign-In Error: $anonErr');
        return null;
      }
    }
  }

  /// Check if user is signed in.
  static bool get isSignedIn => _auth.currentUser != null;
  static String? get currentUid => _auth.currentUser?.uid;

  // ─────────────────────────────────────────────────────────────────────────
  // PROFILE RESTORE
  // Called when a returning user signs in and their Firestore doc exists.
  // Writes all cloud values into SharedPreferences so the app behaves as
  // if the user never uninstalled / switched devices.
  // ─────────────────────────────────────────────────────────────────────────
  static Future<void> _restoreProfileFromCloud(
      Map<String, dynamic> data, User user) async {
    // ── Identity ──
    await LocalStorage.setUserName(data['name'] ?? user.displayName ?? '');
    await LocalStorage.setCountry(data['country'] ?? '');
    await LocalStorage.setCity(data['city'] ?? '');

    // ── Scores (start where the user left off) ──
    await LocalStorage.setBaseScore((data['score'] as num?)?.toInt() ?? 0);
    await LocalStorage.setBaseStreak((data['streak'] as num?)?.toInt() ?? 0);

    // ── Profile fields ──
    final gender = data['gender'] as String?;
    if (gender != null && gender.isNotEmpty) {
      await LocalStorage.setGender(gender);
    }

    final dob = data['dob'] as String?;
    if (dob != null && dob.isNotEmpty) {
      await LocalStorage.setDob(dob);
    }

    final height = (data['height'] as num?)?.toDouble();
    if (height != null && height > 0) {
      await LocalStorage.setHeight(height);
    }

    final heightUnit = data['heightUnit'] as String?;
    if (heightUnit != null && heightUnit.isNotEmpty) {
      await LocalStorage.setHeightUnit(heightUnit);
    }

    final heightFtInch = data['heightFtInch'] as String?;
    if (heightFtInch != null && heightFtInch.isNotEmpty) {
      await LocalStorage.setHeightFtInch(heightFtInch);
    }

    final weight = (data['weight'] as num?)?.toDouble();
    if (weight != null && weight > 0) {
      await LocalStorage.setWeight(weight);
    }

    final weightUnit = data['weightUnit'] as String?;
    if (weightUnit != null && weightUnit.isNotEmpty) {
      await LocalStorage.setWeightUnit(weightUnit);
    }

    // ── Onboarding completion flags ──
    // Only mark a step as done if the user actually completed it before
    // (flag stored as true in Firestore). This guarantees:
    //   • Fresh install on same account  → Permissions → [Basic Info skipped if done] → [DeviceTest skipped if done] → Home
    //   • Re-login on same device        → flags already true locally → router skips all steps → Home
    //   • New device / reinstall         → permissions always shown (device-level grant needed),
    //                                      then Basic Info / Device Test skipped if flags are true in cloud.
    final cloudBasicInfoDone = data['basicInfoDone'] as bool? ?? false;
    final hasLegacyProfileData = (data['dob'] != null && data['dob'].toString().isNotEmpty) || 
                                 (data['height'] != null);
                                 
    if (cloudBasicInfoDone || hasLegacyProfileData) {
      await LocalStorage.setBasicInfoDone();
    }

    final cloudDeviceTestDone = data['deviceTestDone'] as bool? ?? false;
    if (cloudDeviceTestDone || hasLegacyProfileData) {
      await LocalStorage.setDeviceTestDone();
    }

    debugPrint('[FirebaseService] Profile restored from cloud for uid=${user.uid}');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SYNC  — pushes local state to Firestore.
  // Includes the full profile so any future reinstall can restore everything.
  // ─────────────────────────────────────────────────────────────────────────
  static Future<void> syncUserData() async {
    final user = _auth.currentUser;
    if (user == null) return;

    int totalScore = LocalStorage.baseScore;
    int streak = LocalStorage.baseStreak;
    int todayScore = 0;

    try {
      final sessions = StorageService.getSessions();
      if (sessions.isNotEmpty) {
        final now = DateTime.now();
        final todayKey = '${now.year}-${now.month}-${now.day}';
        final Map<String, int> bestDay = {};

        for (final s in sessions) {
          final ins = _insightSvc.compute(
            coughCount: s.coughCount,
            sneezeCount: s.sneezeCount,
            snoreCount: s.snoreCount,
            faceDetected: s.faceDetected,
            brightness: s.brightnessValue,
          );

          totalScore += ins.score;
          if (s.sessionStart.startsWith(todayKey)) {
            todayScore = ins.score;
          }

          try {
            final dt = DateTime.parse(s.sessionStart);
            final key = '${dt.year}-${dt.month}-${dt.day}';
            if ((bestDay[key] ?? 0) < ins.score) bestDay[key] = ins.score;
          } catch (_) {}
        }

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
        streak += localStreak;
      }

      // Full profile payload — everything needed to restore on reinstall / new device.
      final payload = <String, dynamic>{
        // ── Auth & identity ──
        'uid': user.uid,
        'name': LocalStorage.userName.isEmpty
            ? (user.displayName ?? 'Anonymous')
            : LocalStorage.userName,
        'email': user.email,

        // ── Scores ──
        'score': totalScore,
        'streak': streak,
        'todayScore': todayScore,

        // ── Location ──
        'country': LocalStorage.country,
        'city': LocalStorage.city,

        // ── Physical profile ──
        'gender': LocalStorage.gender,
        'dob': LocalStorage.dob,
        'height': LocalStorage.height,
        'heightUnit': LocalStorage.heightUnit,
        'heightFtInch': LocalStorage.heightFtInch,
        'weight': LocalStorage.weight,
        'weightUnit': LocalStorage.weightUnit,

        // ── Onboarding completion flags ──
        'basicInfoDone': LocalStorage.basicInfoDone,
        'deviceTestDone': LocalStorage.deviceTestDone,

        // ── Metadata ──
        'lastUpdated': FieldValue.serverTimestamp(),
      };

      await _db
          .collection('users')
          .doc(user.uid)
          .set(payload, SetOptions(merge: true));

      debugPrint('[FirebaseService] syncUserData: success');
    } catch (e) {
      debugPrint('[FirebaseService] syncUserData error: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LEADERBOARD
  // ─────────────────────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getLeaderboard(
      {String? country, String? city}) async {
    try {
      Query query =
          _db.collection('users').orderBy('score', descending: true);

      if (city != null && city.isNotEmpty) {
        query = query.where('city', isEqualTo: city);
      } else if (country != null && country.isNotEmpty) {
        query = query.where('country', isEqualTo: country);
      }

      final snapshot = await query.limit(50).get();
      return snapshot.docs
          .map((d) => d.data() as Map<String, dynamic>)
          .toList();
    } catch (e) {
      debugPrint('[FirebaseService] getLeaderboard error: $e');
      return [];
    }
  }
}
