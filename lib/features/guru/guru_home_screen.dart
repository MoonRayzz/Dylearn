// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/guru_theme.dart';
import '../../core/services/notification_service.dart';
import 'screens/student_list_screen.dart';
import 'screens/report_tab_screen.dart';
import 'screens/my_books_screen.dart';
import 'screens/guru_settings_screen.dart';

class GuruHomeScreen extends StatefulWidget {
  const GuruHomeScreen({super.key});

  @override
  State<GuruHomeScreen> createState() => _GuruHomeScreenState();
}

class _GuruHomeScreenState extends State<GuruHomeScreen> {
  final ValueNotifier<int> _pageIndex = ValueNotifier<int>(0);
  final NotificationService _notif = NotificationService();
  late final List<Widget> _pages;

  StreamSubscription<QuerySnapshot>? _liveBooksSubscription;
  bool _isInitialLiveLoad = true;

  static const _navItems = [
    _NavItem(icon: Icons.group_rounded, label: 'Murid'),
    _NavItem(icon: Icons.analytics_rounded, label: 'Rapor'),
    _NavItem(icon: Icons.library_books_rounded, label: 'Buku'),
    _NavItem(icon: Icons.settings_rounded, label: 'Pengaturan'),
  ];

  @override
  void initState() {
    super.initState();
    _pages = const [
      StudentListScreen(),
      ReportTabScreen(),
      MyBooksScreen(),
      GuruSettingsScreen(),
    ];
    _setupLiveBookListener();
  }

  void _setupLiveBookListener() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _liveBooksSubscription = FirebaseFirestore.instance
        .collection('library_books')
        .where('uploadBy', isEqualTo: uid)
        .where('status', isEqualTo: 'live')
        .snapshots()
        .listen((snapshot) {
      if (_isInitialLiveLoad) {
        _isInitialLiveLoad = false;
        return;
      }
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final title = change.doc.data()?['title'] ?? 'Buku Anda';
          _notif.showBookStatusNotification(title, true);
        }
      }
    });
  }

  @override
  void dispose() {
    _pageIndex.dispose();
    _liveBooksSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return ValueListenableBuilder<int>(
      valueListenable: _pageIndex,
      builder: (context, currentIndex, _) {
        return Scaffold(
          extendBody: true,
          backgroundColor: GuruTheme.surface,
          body: IndexedStack(
            index: currentIndex,
            children: _pages,
          ),
          bottomNavigationBar: Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              bottom: bottomInset > 0 ? bottomInset : 20,
            ),
            child: _FloatingNav(
              currentIndex: currentIndex,
              items: _navItems,
              onTap: (i) => _pageIndex.value = i,
            ),
          ),
        );
      },
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}

class _FloatingNav extends StatelessWidget {
  final int currentIndex;
  final List<_NavItem> items;
  final ValueChanged<int> onTap;

  const _FloatingNav({
    required this.currentIndex,
    required this.items,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        boxShadow: GuruTheme.navShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.92),
              borderRadius: BorderRadius.circular(32),
            ),
            child: Row(
              children: List.generate(items.length, (i) {
                final active = i == currentIndex;
                final item = items[i];
                return Expanded(
                  child: GestureDetector(
                    onTap: () => onTap(i),
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeInOut,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: active
                                ? GuruTheme.primaryFixed
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            item.icon,
                            size: 22,
                            color: active
                                ? GuruTheme.primary
                                : GuruTheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.label,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 10,
                            fontWeight: active
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: active
                                ? GuruTheme.primary
                                : GuruTheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}