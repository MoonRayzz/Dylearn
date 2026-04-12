// ignore_for_file: curly_braces_in_flow_control_structures, deprecated_member_use, unused_import, sized_box_for_whitespace

import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_animate/flutter_animate.dart'; // DITAMBAHKAN untuk animasi halus

import '../../core/services/auth_service.dart';
import '../../shared/widgets/background_wrapper.dart';
import 'homescreen.dart';
import 'child_profile_screen.dart';
import '../../core/utils/responsive_helper.dart';

// --- 1. SINGLE SOURCE OF TRUTH (GEOMETRY HELPER) ---
class AdventureGeometry {
  static const double nodeHeight = 160.0;

  static double getXForIndex(int i, double centerX, double offset) {
    int pattern = i % 4;
    if (pattern == 0) return centerX;
    if (pattern == 1) return centerX - offset;
    if (pattern == 2) return centerX;
    return centerX + offset;
  }

  static Offset getBezierPoint(
      double t, int fromIndex, int toIndex, double width) {
    final centerX = width / 2;
    final xOffset = width * 0.25;

    double startX = getXForIndex(fromIndex, centerX, xOffset);
    double startY = (fromIndex * nodeHeight) + (nodeHeight / 2);

    double endX = getXForIndex(toIndex, centerX, xOffset);
    double endY = (toIndex * nodeHeight) + (nodeHeight / 2);

    double distY = endY - startY;

    double cp1x = startX;
    double cp1y = startY + (distY / 2);
    double cp2x = endX;
    double cp2y = endY - (distY / 2);

    double u = 1 - t;
    double tt = t * t;
    double uu = u * u;
    double uuu = uu * u;
    double ttt = tt * t;

    double x = (uuu * startX) +
        (3 * uu * t * cp1x) +
        (3 * u * tt * cp2x) +
        (ttt * endX);
    double y = (uuu * startY) +
        (3 * uu * t * cp1y) +
        (3 * u * tt * cp2y) +
        (ttt * endY);

    return Offset(x, y);
  }
}

class AdventureHomeScreen extends StatefulWidget {
  const AdventureHomeScreen({super.key});

  @override
  State<AdventureHomeScreen> createState() => _AdventureHomeScreenState();
}

class _AdventureHomeScreenState extends State<AdventureHomeScreen>
    with TickerProviderStateMixin {
  final AuthService _authService = AuthService();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _todayKey = GlobalKey();

  static final DateFormat _ymdFormat = DateFormat('yyyy-MM-dd');
  static final DateFormat _dayFormat = DateFormat('d');
  static final DateFormat _monthFormat = DateFormat('MMM');

  List<DateTime> _mapDates = [];
  Map<String, int> _dailyMinutes = {};

  bool _isLoading = true;

  final ValueNotifier<bool> _isCheckingProfileNotifier =
      ValueNotifier(false);

  late AnimationController _robotMoveController;
  late Animation<double> _robotAnimation;
  bool _showRocketOverlay = false;
  Alignment _rocketAlignment = Alignment.center;

  final int _daysPast = 7;
  final int _daysFuture = 2;

  Path? _precalculatedPath;
  double _lastCalculatedWidth = 0.0;

  static final Color _appBarBgColor = Colors.white.withOpacity(0.15);
  static final Color _appBarShadowColor = Colors.black.withOpacity(0.05);
  static final Color _pathColor = Colors.black.withOpacity(0.2);
  static final Color _overlayBgColor =
      const Color(0xFFFFF8E1).withOpacity(0.95);

  @override
  void initState() {
    super.initState();
    _initDates();
    _fetchUserActivity();

    _robotMoveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );

    _robotAnimation = CurvedAnimation(
      parent: _robotMoveController,
      curve: Curves.easeInOutCubic,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _jumpToToday();
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) _robotMoveController.forward();
      });
    });
  }

  void _initDates() {
    final now = DateTime.now();
    _mapDates = [];
    for (int i = _daysFuture; i >= 1; i--) {
      _mapDates.add(now.add(Duration(days: i)));
    }
    _mapDates.add(now);
    for (int i = 1; i <= _daysPast; i++) {
      _mapDates.add(now.subtract(Duration(days: i)));
    }
  }

  void _calculatePathIfNeeded(double screenWidth) {
    if (_precalculatedPath != null &&
        _lastCalculatedWidth == screenWidth) {
      return;
    }

    _lastCalculatedWidth = screenWidth;
    final path = Path();
    final centerX = screenWidth / 2;
    final xOffset = screenWidth * 0.25;

    double startX =
        AdventureGeometry.getXForIndex(0, centerX, xOffset);
    double startY = AdventureGeometry.nodeHeight / 2;
    path.moveTo(startX, startY);

    for (int i = 0; i < _mapDates.length - 1; i++) {
      double nextX =
          AdventureGeometry.getXForIndex(i + 1, centerX, xOffset);
      double nextY = startY + AdventureGeometry.nodeHeight;

      double distY = nextY - startY;

      double cp1x = startX;
      double cp1y = startY + (distY / 2);
      double cp2x = nextX;
      double cp2y = nextY - (distY / 2);

      path.cubicTo(cp1x, cp1y, cp2x, cp2y, nextX, nextY);

      startX = nextX;
      startY = nextY;
    }

    final dashedPath = Path();
    for (PathMetric pathMetric in path.computeMetrics()) {
      double distance = 0.0;
      const double dashWidth = 10.0; // Sedikit lebih lebar agar terlihat modern
      const double dashSpace = 8.0;

      while (distance < pathMetric.length) {
        dashedPath.addPath(
          pathMetric.extractPath(distance, distance + dashWidth),
          Offset.zero,
        );
        distance += (dashWidth + dashSpace);
      }
    }
    _precalculatedPath = dashedPath;
  }

  @override
  void dispose() {
    _robotMoveController.dispose();
    _scrollController.dispose();
    _isCheckingProfileNotifier.dispose();
    super.dispose();
  }

  void _jumpToToday() {
    if (_todayKey.currentContext != null) {
      Scrollable.ensureVisible(
        _todayKey.currentContext!,
        alignment: 0.5,
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _fetchUserActivity() async {
    final user = _authService.currentUser;
    if (user == null) return;

    try {
      final now = DateTime.now();
      final startQuery = now.subtract(const Duration(days: 30));

      final query = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('my_library')
          .where('lastAccessed',
              isGreaterThan: Timestamp.fromDate(startQuery))
          .get();

      final Map<String, int> minutesMap = {};

      for (var doc in query.docs) {
        final data = doc.data();
        final ts = data['lastAccessed'];
        if (ts is! Timestamp) continue;
        {
          final date = ts.toDate();
          final String dateKey = _ymdFormat.format(date);

          final rawDuration = data['durationInSeconds'];
          num durationNum = (rawDuration is num) ? rawDuration : 0;
          int minutes = (durationNum / 60).ceil();

          minutesMap[dateKey] =
              (minutesMap[dateKey] ?? 0) + minutes;
        }
      }

      if (mounted) {
        setState(() {
          _dailyMinutes = minutesMap;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error Fetch: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleStartButton() async {
    _isCheckingProfileNotifier.value = true;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (mounted) {
          bool isProfileReady =
              doc.data()?['isProfileComplete'] ?? false;

          if (isProfileReady) {
            _startMissionLaunch();
          } else {
            final result = await Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) =>
                      const ChildProfileScreen()),
            );
            if (result == true) {
              await Future.delayed(
                  const Duration(milliseconds: 300));
              if (mounted) _startMissionLaunch();
            }
          }
        }
      }
    } catch (e) {
      _startMissionLaunch();
    } finally {
      if (mounted) _isCheckingProfileNotifier.value = false;
    }
  }

  Future<void> _startMissionLaunch() async {
    setState(() {
      _showRocketOverlay = true;
      _rocketAlignment = Alignment.center;
    });

    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;

    setState(() {
      _rocketAlignment = const Alignment(0.0, -10.0);
    });

    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const HomeScreen(),
        transitionsBuilder:
            (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 800),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final int todayIndex = _daysFuture;
    final int yesterdayIndex = todayIndex + 1;
    final DateTime now = DateTime.now();
    final String todayStr = _ymdFormat.format(now);

    final double screenWidth = MediaQuery.of(context).size.width;
    final double totalHeight =
        _mapDates.length * AdventureGeometry.nodeHeight;

    final r = context.r;
    final double topPadding = r.spacing(100);
    final double bottomPadding = r.spacing(200);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(r),
      body: Stack(
        children: [
          BackgroundWrapper(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: Colors.orange))
                : Builder(
                    builder: (context) {
                      _calculatePathIfNeeded(screenWidth);

                      if (_precalculatedPath == null) {
                        return const Center(
                          child: CircularProgressIndicator(
                              color: Colors.orange),
                        );
                      }

                      return SingleChildScrollView(
                        controller: _scrollController,
                        physics: const BouncingScrollPhysics(),
                        child: Padding(
                          padding: EdgeInsets.only(
                            top: topPadding,
                            bottom: bottomPadding,
                          ),
                          child: SizedBox(
                            height: totalHeight,
                            child: Stack(
                              children: [
                                // LAYER A: Garis Jalur
                                Positioned.fill(
                                  child: RepaintBoundary(
                                    child: CustomPaint(
                                      painter: _PathPainter(
                                        drawnPath:
                                            _precalculatedPath!,
                                        pathColor: _pathColor,
                                      ),
                                    ),
                                  ),
                                ),

                                // LAYER B: Node Tanggal (Diberi animasi staggered)
                                ...List.generate(
                                    _mapDates.length, (index) {
                                  return _buildMapNodePositioned(
                                    _mapDates[index],
                                    index,
                                    screenWidth,
                                    now,
                                    todayStr,
                                    r,
                                  ).animate(delay: (index * 50).ms)
                                   .fadeIn(duration: 400.ms)
                                   .scale(begin: const Offset(0.8, 0.8), curve: Curves.easeOutBack);
                                }),

                                // LAYER C: Robot Animasi
                                AnimatedBuilder(
                                  animation: _robotAnimation,
                                  builder: (context, child) {
                                    final Offset robotPos =
                                        AdventureGeometry
                                            .getBezierPoint(
                                      _robotAnimation.value,
                                      yesterdayIndex,
                                      todayIndex,
                                      screenWidth,
                                    );

                                    final double robotW = r.size(200);
                                    final double robotH = r.size(240);

                                    return Positioned(
                                      left: robotPos.dx - (robotW / 2),
                                      top: robotPos.dy - robotH,
                                      child: child!,
                                    );
                                  },
                                  child: Container(
                                    width: r.size(200),
                                    height: r.size(240),
                                    // Efek bayangan cahaya di bawah robot
                                    child: Stack(
                                      alignment: Alignment.bottomCenter,
                                      children: [
                                        Container(
                                          width: 60, height: 20,
                                          decoration: BoxDecoration(
                                            boxShadow: [
                                              BoxShadow(color: Colors.orange.withOpacity(0.3), blurRadius: 20, spreadRadius: 5)
                                            ]
                                          ),
                                        ),
                                        Lottie.asset(
                                          'assets/animations/RobotSaludando.json',
                                          fit: BoxFit.contain,
                                          frameRate: FrameRate.max,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),

          if (_showRocketOverlay) _buildRocketOverlay(r),
        ],
      ),
      floatingActionButton:
          _showRocketOverlay ? null : _buildFab(r),
      floatingActionButtonLocation:
          FloatingActionButtonLocation.centerFloat,
    );
  }

  PreferredSizeWidget _buildAppBar(ResponsiveHelper r) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      title: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: r.spacing(20),
              vertical: r.spacing(10),
            ),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.2)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.map_rounded, color: Colors.orange, size: 20),
                SizedBox(width: r.spacing(10)),
                Text(
                  "Peta Petualangan",
                  style: GoogleFonts.comicNeue(
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                    fontSize: r.font(16),
                  ),
                ),
              ],
            ),
          ),
        ),
      ).animate().fadeIn(duration: 600.ms).slideY(begin: -0.5),
      centerTitle: true,
    );
  }

  Widget _buildMapNodePositioned(
    DateTime date,
    int index,
    double screenWidth,
    DateTime now,
    String todayStr,
    ResponsiveHelper r,
  ) {
    final centerX = screenWidth / 2;
    final xOffset = screenWidth * 0.25;
    double nodeX =
        AdventureGeometry.getXForIndex(index, centerX, xOffset);
    double topPos = index * AdventureGeometry.nodeHeight;

    double alignX = (nodeX / screenWidth * 2) - 1.0;

    final String dateKey = _ymdFormat.format(date);
    final int minutesRead = _dailyMinutes[dateKey] ?? 0;

    bool isToday = dateKey == todayStr;
    bool isFuture = date.isAfter(now) && !isToday;

    final String dayNumStr = _dayFormat.format(date);
    final String monthNameStr = _monthFormat.format(date);

    return Positioned(
      top: topPos,
      left: 0,
      right: 0,
      height: AdventureGeometry.nodeHeight,
      child: Align(
        alignment: Alignment(alignX, 0.0),
        child: _AdventureNode(
          key: isToday ? _todayKey : ValueKey(dateKey),
          date: date,
          isToday: isToday,
          isFuture: isFuture,
          minutesRead: minutesRead,
          dayNumStr: dayNumStr,
          monthNameStr: monthNameStr,
          r: r,
          onTap: () {
            if (isToday) {
              _handleStartButton();
            } else if (isFuture) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content:
                        Text("Sabar ya, level ini belum terbuka ⏳")),
              );
            } else {
              if (minutesRead > 0) {
                _showPastSuccessDialog(
                    minutesRead, dayNumStr, monthNameStr, r);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content:
                          Text("Wah, hari ini terlewati. Tetap semangat! 💪")),
                );
              }
            }
          },
        ),
      ),
    );
  }

  Widget _buildRocketOverlay(ResponsiveHelper r) {
    final double rocketSize = r.size(300);

    return Positioned.fill(
      child: Container(
        color: _overlayBgColor,
        child: Stack(
          children: [
            AnimatedAlign(
              alignment: _rocketAlignment,
              duration: const Duration(seconds: 2),
              curve: Curves.easeInBack,
              child: SizedBox(
                width: rocketSize,
                height: rocketSize,
                child: Lottie.asset(
                  'assets/animations/rocket.json',
                  fit: BoxFit.contain,
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding:
                    EdgeInsets.only(bottom: r.spacing(150)),
                child: AnimatedOpacity(
                  opacity: _rocketAlignment == Alignment.center
                      ? 1.0
                      : 0.0,
                  duration: const Duration(milliseconds: 500),
                  child: Text(
                    "Meluncur ke Markas! 🚀",
                    style: GoogleFonts.comicNeue(
                      fontSize: r.font(24),
                      fontWeight: FontWeight.bold,
                      color: Colors.orange.shade800,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFab(ResponsiveHelper r) {
    return ValueListenableBuilder<bool>(
      valueListenable: _isCheckingProfileNotifier,
      builder: (context, isChecking, child) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(color: Colors.orange.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8))
            ]
          ),
          child: SizedBox(
            width: r.size(180),
            height: r.size(60),
            child: FloatingActionButton.extended(
              onPressed: isChecking ? null : _handleStartButton,
              backgroundColor: Colors.orange,
              elevation: 0,
              icon: isChecking
                  ? SizedBox(
                      width: r.size(24),
                      height: r.size(24),
                      child: const CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : Icon(
                      Icons.rocket_launch_rounded,
                      size: r.size(28),
                    ),
              label: Text(
                "Mulai Baca!",
                style: GoogleFonts.comicNeue(
                  fontWeight: FontWeight.bold,
                  fontSize: r.font(20),
                ),
              ),
            ),
          ),
        );
      },
    ).animate().scale(delay: 500.ms, duration: 500.ms, curve: Curves.easeOutBack);
  }

  void _showPastSuccessDialog(
      int mins, String dayNumStr, String monthNameStr,
      ResponsiveHelper r) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: Icon(
          Icons.verified_rounded,
          color: Colors.green,
          size: r.size(60),
        ).animate().scale(duration: 400.ms, curve: Curves.easeOutBack),
        content: Text(
          "Hebat! Kamu sudah membaca $mins menit pada tanggal $dayNumStr $monthNameStr!",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: r.font(14)),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// _AdventureNode (Tampilan Pulau Melayang)
// ─────────────────────────────────────────────
class _AdventureNode extends StatelessWidget {
  final DateTime date;
  final bool isToday;
  final bool isFuture;
  final int minutesRead;
  final String dayNumStr;
  final String monthNameStr;
  final VoidCallback onTap;
  final ResponsiveHelper r;

  const _AdventureNode({
    super.key,
    required this.date,
    required this.isToday,
    required this.isFuture,
    required this.minutesRead,
    required this.dayNumStr,
    required this.monthNameStr,
    required this.onTap,
    required this.r,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDone = minutesRead > 0;
    
    // Warna tema per status
    Color themeColor;
    if (isFuture) themeColor = Colors.grey;
    else if (isToday) themeColor = Colors.orange;
    else if (isDone) themeColor = Colors.green;
    else themeColor = const Color(0xFFEF5350); // Merah lembut untuk terlewat

    final double nodeSize = r.size(85);

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: nodeSize,
            height: nodeSize,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: themeColor.withOpacity(0.2),
                  blurRadius: 15,
                  offset: const Offset(0, 8),
                ),
                // Efek border tipis di dalam agar lebih 3D
                BoxShadow(
                  color: themeColor.withOpacity(0.1),
                  blurRadius: 2,
                  spreadRadius: -2,
                )
              ],
            ),
            child: Container(
              margin: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: themeColor.withOpacity(0.05),
                shape: BoxShape.circle,
                border: Border.all(color: themeColor.withOpacity(isToday ? 0.8 : 0.2), width: 2),
              ),
              child: Center(
                child: isFuture
                    ? Icon(Icons.lock_rounded, color: Colors.grey.shade400, size: r.size(28))
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            dayNumStr,
                            style: GoogleFonts.comicNeue(
                              fontSize: r.font(24),
                              fontWeight: FontWeight.bold,
                              color: themeColor.darken(0.2),
                            ),
                          ),
                          Text(
                            monthNameStr,
                            style: TextStyle(
                              fontSize: r.font(10),
                              color: themeColor.withOpacity(0.7),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
          
          // Badge "Menit" atau "Hari Ini" di bawah node
          if (isToday)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(color: Colors.orange.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))
                ]
              ),
              child: const Text(
                "HARI INI",
                style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5),
              ),
            )
          else if (isDone)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green.shade500,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                "$minutesRead mnt",
                style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }
}

// Extension untuk memudahkan penuaan warna tanpa package eksternal tambahan
extension ColorUtils on Color {
  Color darken([double amount = .1]) {
    assert(amount >= 0 && amount <= 1);
    final hsl = HSLColor.fromColor(this);
    final hslDark = hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));
    return hslDark.toColor();
  }
}

// ─────────────────────────────────────────────
// _PathPainter
// ─────────────────────────────────────────────
class _PathPainter extends CustomPainter {
  final Path drawnPath;
  final Color pathColor;

  _PathPainter({required this.drawnPath, required this.pathColor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = pathColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4 // Sedikit lebih tebal
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(drawnPath, paint);
  }

  @override
  bool shouldRepaint(covariant _PathPainter oldDelegate) {
    return oldDelegate.pathColor != pathColor ||
        oldDelegate.drawnPath != drawnPath;
  }
}