// ignore_for_file: unused_field, deprecated_member_use, use_build_context_synchronously, unnecessary_underscores, unused_local_variable

import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:glassy_real_navbar/glassy_real_navbar.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:showcaseview/showcaseview.dart';
import 'package:flutter_animate/flutter_animate.dart'; // DITAMBAHKAN untuk animasi halus

import 'package:dylearn/core/services/auth_service.dart';
import 'package:dylearn/core/services/notification_service.dart';
import 'package:dylearn/core/services/tutorial_service.dart';
import 'package:dylearn/core/utils/responsive_helper.dart';
import 'package:dylearn/features/student/camera_picker_screen.dart';
import 'package:dylearn/features/student/library_screen.dart';
import 'package:dylearn/features/student/upload_pdf_screen.dart';
import 'package:dylearn/shared/widgets/background_wrapper.dart';
import 'package:dylearn/shared/widgets/quote_widget.dart';
import 'activity_screen.dart';
import 'pengaturan_screen.dart';

class ProfileState {
  final User? user;
  final String? firestoreName;
  const ProfileState({this.user, this.firestoreName});
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AuthService         _authService         = AuthService();
  final NotificationService _notificationService = NotificationService();

  late final ValueNotifier<ProfileState> _profileStateNotifier;
  late final StreamSubscription<User?> _authUserSubscription;

  int  _selectedIndex = 0;
  late final PageController _pageController;

  bool _isTutorialChecked = false;

  final GlobalKey _profileKey = GlobalKey();
  final GlobalKey _quoteKey   = GlobalKey();
  final GlobalKey _scanKey    = GlobalKey();
  final GlobalKey _pdfKey     = GlobalKey();

  late final Map<GlobalKey, String> _showcaseDescriptions;

  StreamSubscription<QuerySnapshot>? _pendingBooksSubscription;
  bool _isInitialPendingLoad = true;

  TextStyle?        _cachedTooltipStyle;
  TextStyle?        _cachedNavBarTextStyle;
  ResponsiveHelper? _r;

  static const BorderRadius _navBarBorderRadius =
      BorderRadius.all(Radius.circular(30)); // Diperhalus lengkungannya

  @override
  void initState() {
    super.initState();
    _pageController = PageController();

    _profileStateNotifier = ValueNotifier(
      ProfileState(user: FirebaseAuth.instance.currentUser),
    );

    _authUserSubscription =
        FirebaseAuth.instance.userChanges().listen((user) {
      if (!mounted) return;
      final String? existingName = _profileStateNotifier.value.firestoreName;
      _profileStateNotifier.value = ProfileState(
        user:          user,
        firestoreName: existingName,
      );
    });

    _fetchDisplayNameFromFirestore();

    _showcaseDescriptions = {
      _profileKey:
          'Ini profilmu! Ketuk area ini untuk membuka Pengaturan dan mengubah foto atau data dirimu.',
      _quoteKey:
          'Setiap hari, akan ada pesan semangat baru untukmu di sini!',
      _scanKey:
          'Punya buku cerita fisik? Foto saja bukunya di sini, nanti sistem akan membacakannya untukmu!',
      _pdfKey:
          'Atau kalau gurumu mengirim tugas dalam bentuk file dokumen (PDF), buka lewat tombol ini ya!',
    };

    _setupNotificationListeners();
  }

  Future<void> _fetchDisplayNameFromFirestore() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users').doc(uid).get();
      if (!mounted) return;
      final name = doc.data()?['displayName'] as String?;
      if (name != null && name.isNotEmpty) {
        final current = _profileStateNotifier.value;
        _profileStateNotifier.value = ProfileState(
          user:          current.user,
          firestoreName: name,
        );
      }
    } catch (e) {
      debugPrint('Gagal fetch nama dari Firestore: $e');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _r = context.r;
    final r          = _r!;
    final fontFamily = Theme.of(context).textTheme.bodyMedium?.fontFamily;
    _cachedTooltipStyle = TextStyle(
      fontFamily: fontFamily, fontSize: r.font(14),
      color: Colors.black87, height: 1.4);
    _cachedNavBarTextStyle = TextStyle(
      fontFamily: fontFamily, fontSize: r.font(10),
      fontWeight: FontWeight.bold);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _profileStateNotifier.dispose();
    _authUserSubscription.cancel();
    _pendingBooksSubscription?.cancel();
    super.dispose();
  }

  void _setupNotificationListeners() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _pendingBooksSubscription = FirebaseFirestore.instance
        .collection('library_books')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snapshot) {
      if (_isInitialPendingLoad) {
        _isInitialPendingLoad = false;
        return;
      }
      for (final change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data();
          if (data != null) {
            final uploadBy = data['uploadBy'] ?? '';
            final voters   = List<dynamic>.from(data['voters'] ?? []);
            if (uploadBy != user.uid && !voters.contains(user.uid)) {
              _notificationService.showJuriCilikNotification();
              break;
            }
          }
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    final r            = _r ?? context.r;

    final double navBarBottomPadding =
        MediaQuery.of(context).padding.bottom + r.spacing(20);
    final double navBarSidePadding = r.spacing(20);

    return ShowCaseWidget(
      onStart: (index, key) {
        final text = _showcaseDescriptions[key];
        if (text != null) TutorialService.speakShowcaseText(text);
      },
      onComplete: (index, key) => TutorialService.stopSpeaking(),
      onFinish:   () => TutorialService.stopSpeaking(),
      builder: (showcaseContext) {
        if (!_isTutorialChecked) {
          _isTutorialChecked = true;
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (!mounted) return;
            final bool hasSeen = await TutorialService.hasSeenTutorial('home');
            if (!hasSeen) {
              ShowCaseWidget.of(showcaseContext).startShowCase(
                  [_profileKey, _quoteKey, _scanKey, _pdfKey]);
              await TutorialService.markTutorialAsSeen('home');
            }
          });
        }

        return Scaffold(
          extendBody: true,
          body: Stack(
            fit: StackFit.expand,
            children: [
              BackgroundWrapper(
                showBottomBlob: false,
                child: PageView(
                  controller:    _pageController,
                  physics:       const NeverScrollableScrollPhysics(),
                  onPageChanged: (index) =>
                      setState(() => _selectedIndex = index),
                  children: [
                    _HomeDashboardContent(
                      profileNotifier: _profileStateNotifier,
                      profileKey:      _profileKey,
                      quoteKey:        _quoteKey,
                      scanKey:         _scanKey,
                      pdfKey:          _pdfKey,
                      tooltipStyle:    _cachedTooltipStyle ??
                                      const TextStyle(fontSize: 14),
                      r: r,
                    ),
                    const LibraryScreen(),
                    const ActivityScreen(),
                    const PengaturanScreen(),
                  ],
                ),
              ),

              // Glassy Navbar with entry animation
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: navBarBottomPadding,
                    left:   navBarSidePadding,
                    right:  navBarSidePadding,
                  ),
                  child: ClipRRect(
                    borderRadius: _navBarBorderRadius,
                    child: RepaintBoundary(
                      child: GlassNavBar(
                        height:              r.size(72),
                        borderRadius:        _navBarBorderRadius,
                        blur:                15,
                        opacity:             0.92,
                        backgroundColor:     Colors.white,
                        barGlassiness:       0.1,
                        lensWidth:           r.size(75),
                        lensHeight:          r.size(60),
                        lensBorderRadius:    BorderRadius.circular(20),
                        lensOpacity:         0.1,
                        glassiness:          40.0,
                        lensRefraction:      1.0,
                        animationEffect:     GlassAnimation.bouncyWater,
                        activeItemAnimation: GlassActiveItemAnimation.none,
                        selectedIndex:       _selectedIndex,
                        onItemSelected: (index) {
                          setState(() => _selectedIndex = index);
                          _pageController.jumpToPage(index);
                        },
                        selectedItemColor:   primaryColor,
                        unselectedItemColor: Colors.black54,
                        showLabels:          true,
                        itemIconSize:        r.size(24),
                        itemTextStyle:       _cachedNavBarTextStyle ??
                                             const TextStyle(fontSize: 10),
                        items: const [
                          GlassNavBarItem(icon: Icons.home_rounded,           title: "Beranda"),
                          GlassNavBarItem(icon: Icons.local_library_rounded, title: "Buku"),
                          GlassNavBarItem(icon: Icons.bar_chart_rounded,     title: "Hasil"),
                          GlassNavBarItem(icon: Icons.settings_rounded,      title: "Atur"),
                        ],
                      ),
                    ),
                  ),
                ),
              ).animate().slideY(begin: 1.5, duration: 600.ms, curve: Curves.easeOutExpo),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
class _HomeDashboardContent extends StatelessWidget {
  final ValueNotifier<ProfileState> profileNotifier;
  final GlobalKey     profileKey;
  final GlobalKey     quoteKey;
  final GlobalKey     scanKey;
  final GlobalKey     pdfKey;
  final TextStyle     tooltipStyle;
  final ResponsiveHelper r;

  const _HomeDashboardContent({
    required this.profileNotifier,
    required this.profileKey,      required this.quoteKey,
    required this.scanKey,         required this.pdfKey,
    required this.tooltipStyle,    required this.r,
  });

  @override
  Widget build(BuildContext context) {
    final primaryColor   = Theme.of(context).primaryColor;
    final secondaryColor = Theme.of(context).colorScheme.secondary;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            r.spacing(24), r.spacing(40), r.spacing(24), r.spacing(120)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // PROFILE SECTION
            Showcase(
              key: profileKey,
              description: 'Ini profilmu! Kamu bisa tekan fotonya untuk mengganti dengan foto yang lebih keren.',
              descTextStyle: tooltipStyle,
              child: ValueListenableBuilder<ProfileState>(
                valueListenable: profileNotifier,
                builder: (_, state, __) => _ProfileHeader(
                  user:          state.user,
                  firestoreName: state.firestoreName,
                  primaryColor:  primaryColor,
                  r: r,
                ),
              ),
            ).animate().fadeIn(duration: 500.ms).slideX(begin: -0.1),

            SizedBox(height: r.spacing(20)),

            // QUOTE SECTION
            Showcase(
              key: quoteKey,
              description: 'Setiap hari, akan ada pesan semangat baru untukmu di sini!',
              descTextStyle: tooltipStyle,
              child: const QuoteWidget(),
            ).animate(delay: 150.ms).fadeIn(duration: 500.ms).slideY(begin: 0.1),

            SizedBox(height: r.spacing(30)),

            Text("Mau ngapain hari ini?",
                style: GoogleFonts.comicNeue(
                    fontSize: r.font(22),
                    fontWeight: FontWeight.bold,
                    color: Colors.black87))
            .animate(delay: 300.ms).fadeIn(),

            SizedBox(height: r.spacing(16)),

            // ACTION CARDS (Scan)
            Showcase(
              key: scanKey,
              description: 'Punya buku cerita fisik? Foto saja bukunya di sini!',
              descTextStyle: tooltipStyle,
              child: _ActionCard(
                title: "Scan Tulisan", subtitle: "Foto buku atau papan",
                iconPath: 'assets/animations/SCANNER.json',
                color: primaryColor, r: r,
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const CameraPickerScreen())),
              ),
            ).animate(delay: 400.ms).fadeIn(duration: 500.ms).slideY(begin: 0.2),

            SizedBox(height: r.spacing(14)),

            // ACTION CARDS (PDF)
            Showcase(
              key: pdfKey,
              description: 'Kalau gurumu mengirim tugas dalam bentuk PDF, buka lewat tombol ini ya!',
              descTextStyle: tooltipStyle,
              child: _ActionCard(
                title: "Baca File Dokumen", subtitle: "Buka file pelajaran",
                iconPath: 'assets/animations/PDF.json',
                color: secondaryColor, r: r,
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const UploadPdfScreen())),
              ),
            ).animate(delay: 550.ms).fadeIn(duration: 500.ms).slideY(begin: 0.2),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
class _ProfileHeader extends StatelessWidget {
  final User?     user;
  final String?   firestoreName;
  final Color     primaryColor;
  final ResponsiveHelper r;

  const _ProfileHeader({
    required this.user,         required this.firestoreName,
    required this.primaryColor, required this.r,
  });

  static String _computeGreeting() {
    final hour = DateTime.now().hour;
    if (hour >= 4  && hour < 11) return 'Selamat Pagi! ☀️';
    if (hour >= 11 && hour < 15) return 'Selamat Siang! 🌤️';
    if (hour >= 15 && hour < 19) return 'Selamat Sore! 🌇';
    return 'Selamat Malam! 🌙';
  }

  @override
  Widget build(BuildContext context) {
    final String  displayName = firestoreName?.isNotEmpty == true
        ? firestoreName!
        : (user?.displayName ?? "Teman");
    final String? photoUrl    = user?.photoURL;
    final String? fontFamily  = Theme.of(context).textTheme.bodyMedium?.fontFamily;
    final double  avatarSize  = r.size(68);

    return Row(
      children: [
        Container(
          height: avatarSize, width: avatarSize,
          decoration: BoxDecoration(
            color: Colors.white, shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: primaryColor.withOpacity(0.2), blurRadius: 12, offset: const Offset(0, 4))
            ],
            border: Border.all(color: Colors.white, width: 2)),
          child: ClipOval(
            child: photoUrl != null
                ? CachedNetworkImage(
                    imageUrl: photoUrl, fit: BoxFit.cover,
                    placeholder: (_, __) => const CircularProgressIndicator(strokeWidth: 2),
                    errorWidget: (_, __, ___) => Icon(
                        Icons.face_rounded, size: r.size(40), color: Colors.orange))
                : Icon(Icons.face_rounded, size: r.size(40), color: Colors.orange),
          ),
        ),
        SizedBox(width: r.spacing(16)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_computeGreeting(),
                  style: GoogleFonts.comicNeue(
                      fontSize: r.font(16), color: Colors.black54,
                      fontWeight: FontWeight.bold)),
              Text(displayName,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontFamily: fontFamily, fontSize: r.font(22),
                      fontWeight: FontWeight.bold, color: Colors.black87)),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
class _ActionCard extends StatelessWidget {
  final String title, subtitle, iconPath;
  final Color color;
  final VoidCallback onTap;
  final ResponsiveHelper r;

  const _ActionCard({
    required this.title,   required this.subtitle,
    required this.iconPath, required this.color,
    required this.onTap,   required this.r,
  });

  @override
  Widget build(BuildContext context) {
    final Color   shadowColor = color.withOpacity(0.08);
    final Color   borderColor = color.withOpacity(0.12);
    final Color   chipBgColor = color.withOpacity(0.1);
    final String? fontFamily  = Theme.of(context).textTheme.bodyMedium?.fontFamily;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: BoxConstraints(minHeight: r.size(135)),
        decoration: BoxDecoration(
          color: Colors.white, 
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04), 
              blurRadius: 20, 
              offset: const Offset(0, 10)
            )
          ],
          border: Border.all(color: borderColor, width: 1.5)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            children: [
              // Subtle background decoration
              Positioned(
                right: -20, top: -20,
                child: CircleAvatar(radius: 50, backgroundColor: color.withOpacity(0.03)),
              ),
              Padding(
                padding: EdgeInsets.all(r.spacing(20)),
                child: Row(
                  children: [
                    Expanded(flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment:  MainAxisAlignment.center,
                        children: [
                          Text(title,
                              style: TextStyle(fontFamily: fontFamily,
                                  fontSize: r.font(18), fontWeight: FontWeight.bold,
                                  color: Colors.black87)),
                          SizedBox(height: r.spacing(6)),
                          Text(subtitle,
                              style: GoogleFonts.comicNeue(
                                  fontSize: r.font(14), color: Colors.grey[600], height: 1.2)),
                          SizedBox(height: r.spacing(14)),
                          Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: r.spacing(14), vertical: r.spacing(6)),
                            decoration: BoxDecoration(
                                color: chipBgColor, borderRadius: BorderRadius.circular(12)),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text("Mulai",
                                    style: TextStyle(color: color,
                                        fontWeight: FontWeight.bold, fontSize: r.font(12))),
                                SizedBox(width: r.spacing(4)),
                                Icon(Icons.arrow_forward_ios_rounded, size: r.font(10), color: color),
                              ],
                            )),
                        ],
                      ),
                    ),
                    Expanded(flex: 2,
                      child: RepaintBoundary(
                        child: Lottie.asset(iconPath,
                            height: r.size(110), fit: BoxFit.contain,
                            frameRate: FrameRate.max,
                            errorBuilder: (_, __, ___) => Icon(
                                Icons.image_not_supported_rounded,
                                size: r.size(50), color: color))),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}