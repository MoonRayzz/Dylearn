// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/auth_service.dart';
import '../welcome_screen.dart';
import '../student/adventure_home_screen.dart';
import '../student/child_profile_screen.dart'; 
import '../guru/guru_home_screen.dart';
import 'parental_consent_dialog.dart';
import '../../core/services/notification_service.dart';

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _hasConsented = false;
  bool _isLoadingConsent = true;

  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _checkConsent();
  }

  Future<void> _checkConsent() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _hasConsented = prefs.getBool('has_consented') ?? false;
        _isLoadingConsent = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingConsent) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Colors.orange)),
      );
    }

    if (!_hasConsented) {
      return Stack(
        children: [
          const WelcomeScreen(),
          Container(
            color: Colors.black54,
            child: ParentalConsentDialog(
              onAgreed: () async {
                setState(() => _hasConsented = true);
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('has_consented', true);
                await NotificationService().requestPermission();
              },
            ),
          ),
        ],
      );
    }

    return StreamBuilder<User?>(
      stream: _authService.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator(color: Colors.orange)),
          );
        }

        if (snapshot.hasData) {
          return _CheckProfileWrapper(user: snapshot.data!);
        }

        return const WelcomeScreen();
      },
    );
  }
}

class _CheckProfileWrapper extends StatelessWidget {
  final User user;
  const _CheckProfileWrapper({required this.user});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots(),
      builder: (context, userSnap) {
        if (userSnap.hasError) {
          return const Scaffold(
            body: Center(
              child: Icon(Icons.error_outline, color: Colors.orange, size: 48),
            ),
          );
        }

        // ── FIX: tunggu sampai snapshot dan datanya benar-benar ada ──
        if (!userSnap.hasData ||
            !userSnap.data!.exists ||
            userSnap.data!.data() == null) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: Colors.orange),
            ),
          );
        }

        final userData = userSnap.data!.data() as Map<String, dynamic>;

        // ── FIX: Cegah routing menggunakan data parsial (optimistic update) ──
        // Jika document tidak memiliki field 'role', artinya ini hanya pembaruan sementara
        // dari fungsi set({lastLogin: ...}, merge: true) dan data utuh belum turun dari server.
        if (!userData.containsKey('role')) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: Colors.orange),
            ),
          );
        }

        final String role = userData['role'] ?? 'user';
        final bool isProfileComplete = userData['isProfileComplete'] ?? false;

        // Routing berdasarkan Role
        if (role == 'guru') {
          return const GuruHomeScreen();
        }

        if (!isProfileComplete) {
          return const ChildProfileScreen();
        }

        return const AdventureHomeScreen();
      },
    );
  }
}