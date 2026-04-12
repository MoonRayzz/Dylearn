// ignore_for_file: curly_braces_in_flow_control_structures, deprecated_member_use, use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:showcaseview/showcaseview.dart';
import '../../core/services/tutorial_service.dart';

import '../../core/services/auth_service.dart';
import '../../shared/widgets/background_wrapper.dart';
import '../../core/utils/responsive_helper.dart';
import '../read_screen.dart';

class ActivityData {
  final Map<String, List<QueryDocumentSnapshot>> groupedHistory;
  final Map<int, double> weeklyMinutes;
  final double minutesToday;

  const ActivityData({
    required this.groupedHistory,
    required this.weeklyMinutes,
    required this.minutesToday,
  });
}

class ActivityScreen extends StatefulWidget {
  // PARAMETER BARU UNTUK SESI GURU
  final String? activeStudentUid;
  final String? activeStudentName;

  const ActivityScreen({
    super.key,
    this.activeStudentUid,
    this.activeStudentName,
  });

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen>
    with AutomaticKeepAliveClientMixin {
  final AuthService _authService = AuthService();
  late Stream<QuerySnapshot> _activityStream;
  int _dataLimit = 20;

  bool _isTutorialChecked = false;

  final GlobalKey _bannerKey = GlobalKey();
  final GlobalKey _chartKey = GlobalKey();
  final GlobalKey _historyKey = GlobalKey();

  late final Map<GlobalKey, String> _showcaseDescriptions;

  static final DateFormat _groupedDateFormat =
      DateFormat('d MMMM yyyy', 'id_ID');

  // OPTIMIZATION: Cache GoogleFonts base → static final
  static final TextStyle _comicNueBase = GoogleFonts.comicNeue(
    fontWeight: FontWeight.bold,
  );

  // HELPER UNTUK MENDAPATKAN UID TARGET
  String get _targetUid => widget.activeStudentUid ?? _authService.currentUser?.uid ?? '';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initStream();

    _showcaseDescriptions = {
      _bannerKey:
          'Ayo kumpulkan menit membacamu hari ini agar dapat animasi spesial!',
      _chartKey:
          'Grafik ini menunjukkan berapa lama kamu membaca setiap harinya selama seminggu terakhir.',
      _historyKey:
          'Buku yang sudah kamu scan atau buka akan otomatis tersimpan di sini. Tekan dan tahan (long press) jika kamu ingin menghapusnya.',
    };
  }

  void _initStream() {
    final user = _authService.currentUser;
    if (user == null) return;

    Query query = FirebaseFirestore.instance
        .collection('users')
        .doc(_targetUid) // GUNAKAN TARGET UID
        .collection('my_library');

    // JIKA GURU, FILTER HANYA TUGAS YANG DIBERIKAN GURU INI
    if (widget.activeStudentUid != null) {
      query = query.where('createdBy', isEqualTo: user.uid);
    }

    _activityStream = query
        .orderBy('lastAccessed', descending: true)
        .limit(_dataLimit)
        .snapshots();
  }

  void _loadMore() {
    setState(() {
      _dataLimit += 20;
      _initStream();
    });
  }

  static ActivityData _processSnapshotData(
      List<QueryDocumentSnapshot> docs) {
    final Map<String, QueryDocumentSnapshot> uniqueDocs = {
      for (var doc in docs) doc.id: doc
    };

    final List<QueryDocumentSnapshot> sortedDocs =
        uniqueDocs.values.toList();

    final Map<String, List<QueryDocumentSnapshot>> groupedHistory =
        {};
    final Map<int, double> weeklyMinutes = {
      0: 0.0, 1: 0.0, 2: 0.0,
      3: 0.0, 4: 0.0, 5: 0.0, 6: 0.0
    };

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    for (var doc in sortedDocs) {
      final Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
      final timestamp =
          (data['lastAccessed'] as Timestamp?)?.toDate() ??
              DateTime(2000);
      final docDate = DateTime(
          timestamp.year, timestamp.month, timestamp.day);

      String groupKey;
      if (docDate == today)
        groupKey = "Hari Ini";
      else if (docDate == yesterday)
        groupKey = "Kemarin";
      else
        groupKey = _groupedDateFormat.format(docDate);

      groupedHistory.putIfAbsent(groupKey, () => []).add(doc);

      final dayDiff = today.difference(docDate).inDays;
      if (dayDiff >= 0 && dayDiff < 7) {
        final int graphIndex = 6 - dayDiff;
        final rawDuration = data['durationInSeconds'];
        final double durationSec =
            (rawDuration is num) ? rawDuration.toDouble() : 0.0;
        weeklyMinutes[graphIndex] =
            (weeklyMinutes[graphIndex] ?? 0.0) +
                (durationSec / 60.0);
      }
    }

    return ActivityData(
      groupedHistory: groupedHistory,
      weeklyMinutes: weeklyMinutes,
      minutesToday: weeklyMinutes[6] ?? 0.0,
    );
  }

  Future<void> _deleteHistoryItem(
      String docId, String title) async {
    final user = _authService.currentUser;
    if (user == null) return;

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Text("Hapus Riwayat?",
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text(
            "Kamu yakin ingin menghapus '$title'?\n\nData tidak bisa dikembalikan."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Batal",
                style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Hapus",
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // BUG FIX #4: mounted guard sebelum showDialog loading
    if (!mounted) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) =>
          const Center(child: CircularProgressIndicator()),
    );

    try {
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(_targetUid) // GUNAKAN TARGET UID
          .collection('my_library')
          .doc(docId);
      final docSnap = await docRef.get();

      if (docSnap.exists) {
        final data = docSnap.data() as Map<String, dynamic>;
        final List<Future> deleteTasks = [];

        if (data['imageUrls'] is List) {
          // BUG FIX #2: .whereType<String>() — hindari TypeError
          // jika list berisi dynamic/non-String
          for (final String url
              in (data['imageUrls'] as List)
                  .whereType<String>()) {
            deleteTasks.add(
              FirebaseStorage.instance
                  .refFromURL(url)
                  .delete()
                  .catchError((_) {}),
            );
          }
        } else if (data['imageUrl'] != null &&
            data['imageUrl'] != '') {
          deleteTasks.add(
            FirebaseStorage.instance
                .refFromURL(data['imageUrl'] as String)
                .delete()
                .catchError((_) {}),
          );
        }

        await Future.wait(deleteTasks);
        await docRef.delete();
      }

      if (navigator.canPop()) navigator.pop();
      messenger.showSnackBar(const SnackBar(
        content: Text("Berhasil dihapus"),
        backgroundColor: Colors.green,
      ));
    } catch (e) {
      if (navigator.canPop()) navigator.pop();
      messenger.showSnackBar(SnackBar(
        content: Text("Gagal: $e"),
        backgroundColor: Colors.red,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final user = _authService.currentUser;
    // JIKA MODE GURU, TAMPILKAN NAMA MURID DI BANNER
    final String userName = widget.activeStudentName ?? user?.displayName ?? 'Jagoan';

    // RESPONSIVENESS: Compute helper sekali per build
    final ResponsiveHelper r = context.r;

    // BUG FIX #1: Compute tooltipStyle sekali — ganti 3x _getTooltipStyle(context)
    final TextStyle tooltipStyle = TextStyle(
      fontFamily:
          Theme.of(context).textTheme.bodyMedium?.fontFamily,
      fontSize: r.font(14),
      color: Colors.black87,
      height: 1.4,
    );

    return ShowCaseWidget(
      enableAutoScroll: true,
      scrollDuration: const Duration(milliseconds: 800),
      onStart: (index, key) {
        final text = _showcaseDescriptions[key];
        if (text != null)
          TutorialService.speakShowcaseText(text);
      },
      onComplete: (index, key) =>
          TutorialService.stopSpeaking(),
      onFinish: () => TutorialService.stopSpeaking(),
      builder: (showcaseContext) {
        if (!_isTutorialChecked) {
          _isTutorialChecked = true;
          WidgetsBinding.instance
              .addPostFrameCallback((_) async {
            final bool hasSeen =
                await TutorialService.hasSeenTutorial(
                    'activity');
            if (!hasSeen && mounted) {
              ShowCaseWidget.of(showcaseContext).startShowCase([
                _bannerKey,
                _chartKey,
                _historyKey,
              ]);
              await TutorialService.markTutorialAsSeen(
                  'activity');
            }
          });
        }

        return Scaffold(
          backgroundColor: const Color(0xFFFDFDFD),
          appBar: AppBar(
            title: Text(
              widget.activeStudentUid != null 
                  ? "Progres $userName" 
                  : "Laporan Progresmu",
              style: _comicNueBase.copyWith(
                color: Colors.black87,
              ),
            ),
            centerTitle: true,
            backgroundColor: Colors.transparent,
            elevation: 0,
            iconTheme:
                const IconThemeData(color: Colors.black87),
          ),
          body: BackgroundWrapper(
            showBottomBlob: false,
            child: StreamBuilder<QuerySnapshot>(
              stream: _activityStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(
                        color: Colors.orange),
                  );
                }
                if (snapshot.hasError)
                  return _ErrorView(
                    onRetry: () =>
                        setState(() => _initStream()),
                    r: r,
                  );
                if (!snapshot.hasData ||
                    snapshot.data!.docs.isEmpty)
                  return _EmptyView(
                    userName: userName,
                    r: r,
                  );

                final ActivityData activityData =
                    _processSnapshotData(
                        snapshot.data!.docs);
                final bool showLoadMoreButton =
                    snapshot.data!.docs.length >= _dataLimit;

                return CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.symmetric(
                        horizontal: r.spacing(20),
                        vertical: r.spacing(10),
                      ),
                      sliver: SliverList(
                        delegate:
                            SliverChildListDelegate.fixed([
                          Showcase(
                            key: _bannerKey,
                            description:
                                _showcaseDescriptions[
                                    _bannerKey]!,
                            descTextStyle: tooltipStyle,
                            child: _AppreciationBanner(
                              name: userName,
                              minutes:
                                  activityData.minutesToday,
                              r: r,
                            ),
                          ),
                          SizedBox(height: r.spacing(30)),
                          _SectionHeader(
                            title: "Statistik Belajar",
                            icon: Icons.bar_chart_rounded,
                            r: r,
                          ),
                          SizedBox(height: r.spacing(16)),
                          Showcase(
                            key: _chartKey,
                            description:
                                _showcaseDescriptions[
                                    _chartKey]!,
                            descTextStyle: tooltipStyle,
                            child: _ChartCard(
                              data: activityData.weeklyMinutes,
                              r: r,
                            ),
                          ),
                          SizedBox(height: r.spacing(30)),
                          Showcase(
                            key: _historyKey,
                            description:
                                _showcaseDescriptions[
                                    _historyKey]!,
                            descTextStyle: tooltipStyle,
                            child: _SectionHeader(
                              title: "Riwayat Membaca",
                              icon: Icons.history_edu_rounded,
                              r: r,
                            ),
                          ),
                          SizedBox(height: r.spacing(16)),
                        ]),
                      ),
                    ),

                    ...activityData.groupedHistory.entries
                        .map((entry) {
                      return SliverMainAxisGroup(
                        slivers: [
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                r.spacing(24),
                                r.spacing(10),
                                r.spacing(20),
                                r.spacing(10),
                              ),
                              child: Text(
                                entry.key,
                                style: _comicNueBase.copyWith(
                                  fontSize: r.font(16),
                                  color: Colors.grey[700],
                                ),
                              ),
                            ),
                          ),
                          SliverPadding(
                            padding: EdgeInsets.symmetric(
                              horizontal: r.spacing(20),
                            ),
                            sliver: SliverList(
                              delegate:
                                  SliverChildBuilderDelegate(
                                (context, index) {
                                  final doc =
                                      entry.value[index];
                                  return Padding(
                                    padding: EdgeInsets.only(
                                      bottom: r.spacing(16),
                                    ),
                                    child: _HistoryItemCard(
                                      key: ValueKey(doc.id),
                                      doc: doc,
                                      onDelete: (id, title) =>
                                          _deleteHistoryItem(
                                              id, title),
                                      r: r,
                                      // TERUSKAN KE CARD AGAR BISA DIBUKA
                                      activeStudentUid: widget.activeStudentUid, 
                                    ),
                                  );
                                },
                                childCount: entry.value.length,
                              ),
                            ),
                          ),
                        ],
                      );
                    }),

                    SliverToBoxAdapter(
                      child: Padding(
                        padding:
                            EdgeInsets.all(r.spacing(20)),
                        child: showLoadMoreButton
                            ? TextButton(
                                onPressed: _loadMore,
                                child: Text(
                                  "Lihat Lebih Banyak ⬇️",
                                  style:
                                      _comicNueBase.copyWith(
                                    color:
                                        Colors.orange.shade800,
                                    fontSize: r.font(16),
                                  ),
                                ),
                              )
                            : Text(
                                "Semua riwayat sudah ditampilkan 🎉",
                                textAlign: TextAlign.center,
                                style: _comicNueBase.copyWith(
                                  color: Colors.grey,
                                  fontWeight: FontWeight.normal,
                                ),
                              ),
                      ),
                    ),

                    SliverToBoxAdapter(
                        child: SizedBox(height: r.spacing(80))),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// APPRECIATION BANNER
// ══════════════════════════════════════════════════════════════════

class _AppreciationBanner extends StatelessWidget {
  final String name;
  final double minutes;
  final ResponsiveHelper r;

  // OPTIMIZATION: Cache shadow/border colors → static final
  static final Color _shadowColor =
      Colors.orange.withOpacity(0.08);
  static final Color _borderColor =
      Colors.orange.withOpacity(0.1);

  // OPTIMIZATION: Cache GoogleFonts base → static final
  static final TextStyle _comicNueBase = GoogleFonts.comicNeue(
    fontWeight: FontWeight.bold,
  );

  // OPTIMIZATION: Cache pill decoration → static final
  static final BoxDecoration _pillDecoration = BoxDecoration(
    color: Colors.blue.shade50,
    borderRadius: BorderRadius.circular(30),
  );

  const _AppreciationBanner({
    required this.name,
    required this.minutes,
    required this.r,
  });

  @override
  Widget build(BuildContext context) {
    String message;
    String animationAsset;
    if (minutes >= 50) {
      message = "Luar biasa! Kamu juara membaca!";
      animationAsset = 'assets/animations/Rewards.json';
    } else if (minutes >= 25) {
      message = "Hebat! Sedikit lagi target tercapai!";
      animationAsset = 'assets/animations/Rewards (1).json';
    } else {
      message = minutes > 0
          ? "Awal yang bagus! Lanjutkan bacanya."
          : "Yuk mulai membaca hari ini!";
      animationAsset =
          'assets/animations/Reward light effect.json';
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(r.spacing(20)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            // OPTIMIZATION: Cached shadow color
            color: _shadowColor,
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
        // OPTIMIZATION: Cached border color
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        children: [
          SizedBox(
            // RESPONSIVENESS: Responsive Lottie height
            height: r.size(150),
            child: RepaintBoundary(
              child: Lottie.asset(
                animationAsset,
                repeat: false,
                fit: BoxFit.contain,
                frameRate: FrameRate.max,
                errorBuilder: (c, e, s) => Icon(
                  Icons.stars_rounded,
                  // RESPONSIVENESS: Responsive icon
                  size: r.size(80),
                  color: Colors.orange,
                ),
              ),
            ),
          ),
          Text(
            "Hai, $name!",
            style: _comicNueBase.copyWith(
              // RESPONSIVENESS: Responsive font
              fontSize: r.font(26),
              color: Colors.orange.shade800,
            ),
          ),
          SizedBox(height: r.spacing(8)),
          Text(
            message,
            textAlign: TextAlign.center,
            style: _comicNueBase.copyWith(
              // RESPONSIVENESS: Responsive font
              fontSize: r.font(16),
              color: Colors.black54,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: r.spacing(16)),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: r.spacing(20),
              vertical: r.spacing(10),
            ),
            // OPTIMIZATION: Cached static decoration
            decoration: _pillDecoration,
            child: Text(
              "${minutes.toStringAsFixed(0)} Menit Membaca Hari Ini",
              style: _comicNueBase.copyWith(
                color: Colors.blue.shade700,
                // RESPONSIVENESS: Responsive font
                fontSize: r.font(16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// SECTION HEADER
// ══════════════════════════════════════════════════════════════════

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final ResponsiveHelper r;

  // OPTIMIZATION: Cache icon container decoration → static final
  static final BoxDecoration _iconDecoration = BoxDecoration(
    color: Colors.blue.shade50,
    borderRadius: BorderRadius.circular(12),
  );

  // OPTIMIZATION: Cache icon color → static final
  static final Color _iconColor = Colors.blue.shade700;

  // OPTIMIZATION: Cache GoogleFonts base → static final
  static final TextStyle _comicNueBase = GoogleFonts.comicNeue(
    fontWeight: FontWeight.bold,
  );

  const _SectionHeader({
    required this.title,
    required this.icon,
    required this.r,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(r.spacing(8)),
          // OPTIMIZATION: Cached static decoration
          decoration: _iconDecoration,
          child: Icon(
            icon,
            // OPTIMIZATION: Cached color
            color: _iconColor,
            // RESPONSIVENESS: Responsive icon
            size: r.size(20),
          ),
        ),
        SizedBox(width: r.spacing(12)),
        Text(
          title,
          style: _comicNueBase.copyWith(
            // RESPONSIVENESS: Responsive font
            fontSize: r.font(20),
            color: Colors.black87,
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// CHART CARD
// ══════════════════════════════════════════════════════════════════

class _ChartCard extends StatelessWidget {
  final Map<int, double> data;
  final ResponsiveHelper r;

  static final DateFormat _dayFormat = DateFormat.E('id_ID');

  // OPTIMIZATION: Cache GoogleFonts for tooltip → static final
  static final TextStyle _tooltipStyle = GoogleFonts.comicNeue(
    color: Colors.white,
    fontWeight: FontWeight.bold,
  );

  // OPTIMIZATION: Cache chart shadow color → static final
  static final Color _shadowColor =
      Colors.black.withOpacity(0.03);

  const _ChartCard({
    required this.data,
    required this.r,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final List<String> days = List.generate(
      7,
      (i) => _dayFormat.format(
          now.subtract(Duration(days: 6 - i))),
    );

    double maxY = data.values.isEmpty
        ? 10
        : data.values.reduce((a, b) => a > b ? a : b) + 5;
    if (maxY < 10) maxY = 10;

    return RepaintBoundary(
      child: Container(
        // RESPONSIVENESS: Responsive height
        height: r.size(240),
        padding: EdgeInsets.fromLTRB(
          r.spacing(16),
          r.spacing(32),
          r.spacing(16),
          r.spacing(10),
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              // OPTIMIZATION: Cached shadow color
              color: _shadowColor,
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: maxY,
            barTouchData: BarTouchData(
              enabled: true,
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (group) =>
                    Colors.blueAccent,
                getTooltipItem:
                    (group, groupIndex, rod, rodIndex) =>
                        BarTooltipItem(
                  '${rod.toY.toInt()} mnt',
                  // OPTIMIZATION: Cached tooltip style
                  _tooltipStyle,
                ),
              ),
            ),
            titlesData: FlTitlesData(
              leftTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false)),
              topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (value, meta) {
                    final int idx = value.toInt();
                    if (idx >= 0 && idx < days.length) {
                      return Padding(
                        padding:
                            const EdgeInsets.only(top: 8.0),
                        child: Text(
                          days[idx],
                          style: GoogleFonts.comicNeue(
                            // RESPONSIVENESS
                            fontSize: r.font(12),
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    }
                    return const SizedBox();
                  },
                ),
              ),
            ),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: maxY / 5,
              getDrawingHorizontalLine: (value) => FlLine(
                color: Colors.grey.shade100,
                strokeWidth: 1,
              ),
            ),
            borderData: FlBorderData(show: false),
            barGroups: List.generate(
              7,
              (index) => BarChartGroupData(
                x: index,
                barRods: [
                  BarChartRodData(
                    toY: data[index] ?? 0.0,
                    color: index == 6
                        ? const Color(0xFFFF9F1C)
                        : const Color(0xFFBFDBFE),
                    width: 16,
                    borderRadius: BorderRadius.circular(8),
                    backDrawRodData:
                        BackgroundBarChartRodData(
                      show: true,
                      toY: maxY,
                      color: Colors.grey.shade50,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// HISTORY ITEM CARD
// ══════════════════════════════════════════════════════════════════

class _HistoryItemCard extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  final Function(String, String) onDelete;
  final ResponsiveHelper r;
  // DITAMBAHKAN: Parameter agar Card tahu UID murid yang sedang aktif
  final String? activeStudentUid;

  static final DateFormat _timeFormat = DateFormat('HH:mm');

  // BUG FIX #5: Pre-compiled regex — bukan RegExp() inline baru setiap build
  static final RegExp _reSentence = RegExp(r'[.!?]+');

  // OPTIMIZATION: Cache shadow color → static final
  static final Color _shadowColor =
      const Color(0xFF1D1617).withOpacity(0.07);

  // OPTIMIZATION: Cache card/thumbnail BorderRadius → static final
  static final BorderRadius _cardRadius =
      BorderRadius.circular(20);
  static final BorderRadius _thumbnailRadius =
      BorderRadius.circular(14);
  static final BorderRadius _progressRadius =
      BorderRadius.circular(4);

  // OPTIMIZATION: Cache GoogleFonts base → static final
  static final TextStyle _comicNueBase = GoogleFonts.comicNeue(
    fontWeight: FontWeight.bold,
  );

  // OPTIMIZATION: Cache default status color → static final
  static final Color _defaultStatusColor =
      Colors.orange.shade400;

  const _HistoryItemCard({
    super.key,
    required this.doc,
    required this.onDelete,
    required this.r,
    this.activeStudentUid,
  });

  String _toTitleCase(String text) {
    if (text.isEmpty) return text;
    try {
      return text.split(' ').map((word) {
        if (word.isEmpty) return word;
        return word[0].toUpperCase() +
            word.substring(1).toLowerCase();
      }).join(' ');
    } catch (e) {
      return text;
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = doc.data() as Map<String, dynamic>;
    final String docId = doc.id;

    String rawTitle = (data['title'] as String?) ??
        (data['ocrText'] as String? ?? 'Dokumen Tanpa Judul');
    if (rawTitle.contains('\n'))
      rawTitle = rawTitle.split('\n').first;
    String title = _toTitleCase(rawTitle);
    if (title.length > 35)
      title = "${title.substring(0, 35)}...";

    final String? thumbnailUrl =
        data['imageUrl'] ?? data['coverUrl'];
    final time =
        (data['lastAccessed'] as Timestamp?)?.toDate();
    final String type = data['fileType'] ?? 'image';

    final Color accentColor =
        type == 'pdf' ? Colors.redAccent : Colors.blueAccent;
    final IconData iconType = type == 'pdf'
        ? Icons.picture_as_pdf_rounded
        : Icons.camera_alt_rounded;

    final num rawLastIndex = data['lastSentenceIndex'] ?? 0;
    final num rawTotalSentences =
        data['totalSentences'] ?? 0;

    final int lastIndex = rawLastIndex.toInt();
    int totalSentences = rawTotalSentences.toInt();

    if (totalSentences == 0 && data['ocrText'] != null) {
      final String fullText = data['ocrText'] as String;
      if (fullText.isNotEmpty) {
        // BUG FIX #5: Gunakan pre-compiled _reSentence
        totalSentences = fullText.split(_reSentence).length;
      }
    }

    final bool isFinished = data['isFinished'] ?? false;
    double progressValue = 0.0;
    String statusLabel = "Baru";
    // OPTIMIZATION: Use cached default color
    Color statusColor = _defaultStatusColor;

    if (isFinished) {
      progressValue = 1.0;
      statusLabel = "Selesai ✅";
      statusColor = Colors.green.shade500;
    } else if (totalSentences > 0) {
      progressValue = lastIndex / totalSentences;
      if (progressValue < 0) progressValue = 0.0;
      if (progressValue > 1) progressValue = 1.0;
      if (progressValue > 0) {
        statusLabel =
            "${(progressValue * 100).toInt()}% Dibaca";
        if (progressValue > 0.5)
          statusColor = Colors.blue.shade500;
      }
    }

    // OPTIMIZATION: Compute thumbnail bg color once per build
    final Color thumbnailBg =
        (thumbnailUrl != null && thumbnailUrl.isNotEmpty)
            ? Colors.grey.shade200
            : accentColor.withOpacity(0.1);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        // OPTIMIZATION: Cached radius
        borderRadius: _cardRadius,
        boxShadow: [
          BoxShadow(
            // OPTIMIZATION: Cached shadow color
            color: _shadowColor,
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: _cardRadius,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (c) => ReadScreen(
                  text: data['ocrText'] ?? '',
                  documentId: docId,
                  initialIndex: lastIndex,
                  imageUrls: data['imageUrls'] != null
                      ? List<String>.from(data['imageUrls'])
                      : null,
                  // TERUSKAN PARAMETER GURU KE READ SCREEN
                  activeStudentUid: activeStudentUid, 
                ),
              ),
            );
          },
          onLongPress: () => onDelete(docId, title),
          child: Padding(
            padding: EdgeInsets.all(r.spacing(16)),
            child: Row(
              children: [
                Container(
                  // RESPONSIVENESS: Responsive thumbnail
                  width: r.size(50),
                  height: r.size(50),
                  decoration: BoxDecoration(
                    // OPTIMIZATION: Pre-computed color
                    color: thumbnailBg,
                    // OPTIMIZATION: Cached radius
                    borderRadius: _thumbnailRadius,
                    image: (thumbnailUrl != null &&
                            thumbnailUrl.isNotEmpty)
                        ? DecorationImage(
                            image: CachedNetworkImageProvider(
                                thumbnailUrl),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: (thumbnailUrl != null &&
                          thumbnailUrl.isNotEmpty)
                      ? null
                      : Icon(
                          iconType,
                          color: accentColor,
                          // RESPONSIVENESS: Responsive icon
                          size: r.size(26),
                        ),
                ),
                SizedBox(width: r.spacing(16)),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: _comicNueBase.copyWith(
                          // RESPONSIVENESS: Responsive font
                          fontSize: r.font(16),
                          color: const Color(0xFF1D1617),
                          height: 1.2,
                        ),
                      ),
                      SizedBox(height: r.spacing(6)),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time_rounded,
                            // RESPONSIVENESS: Responsive icon
                            size: r.size(12),
                            color: Colors.grey.shade500,
                          ),
                          SizedBox(width: r.spacing(4)),
                          Text(
                            time != null
                                ? _timeFormat.format(time)
                                : "-",
                            style: _comicNueBase.copyWith(
                              // RESPONSIVENESS
                              fontSize: r.font(12),
                              color: Colors.grey.shade500,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: r.spacing(10)),
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              // OPTIMIZATION: Cached radius
                              borderRadius: _progressRadius,
                              child: LinearProgressIndicator(
                                value: progressValue,
                                backgroundColor:
                                    Colors.grey.shade100,
                                color: statusColor,
                                minHeight: 6,
                              ),
                            ),
                          ),
                          SizedBox(width: r.spacing(8)),
                          Text(
                            statusLabel,
                            style: _comicNueBase.copyWith(
                              // RESPONSIVENESS
                              fontSize: r.font(10),
                              color: statusColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(width: r.spacing(12)),
                Icon(
                  isFinished
                      ? Icons.check_circle_rounded
                      : Icons.play_circle_fill_rounded,
                  color: isFinished
                      ? Colors.green.shade300
                      : Colors.orange.shade300,
                  // RESPONSIVENESS: Responsive icon
                  size: r.size(32),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// EMPTY VIEW
// ══════════════════════════════════════════════════════════════════

class _EmptyView extends StatelessWidget {
  final String userName;
  final ResponsiveHelper r;

  // OPTIMIZATION: Cache icon color → static final
  static final Color _emptyIconColor = Colors.grey.shade300;

  // OPTIMIZATION: Cache GoogleFonts base → static final
  static final TextStyle _comicNueBase = GoogleFonts.comicNeue(
    fontWeight: FontWeight.bold,
  );

  const _EmptyView({required this.userName, required this.r});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.all(r.spacing(20)),
      children: [
        _AppreciationBanner(
          name: userName,
          minutes: 0.0,
          r: r,
        ),
        SizedBox(height: r.spacing(50)),
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.menu_book_rounded,
                // RESPONSIVENESS: Responsive icon
                size: r.size(80),
                // OPTIMIZATION: Cached color
                color: _emptyIconColor,
              ),
              SizedBox(height: r.spacing(16)),
              Text(
                "Belum ada riwayat membaca.",
                style: _comicNueBase.copyWith(
                  color: Colors.grey,
                  // RESPONSIVENESS: Responsive font
                  fontSize: r.font(16),
                ),
              ),
              SizedBox(height: r.spacing(8)),
              Text(
                "Hasil scan & upload kamu akan muncul di sini.",
                style: _comicNueBase.copyWith(
                  color: Colors.grey.shade400,
                  // RESPONSIVENESS: Responsive font
                  fontSize: r.font(14),
                  fontWeight: FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// ERROR VIEW
// ══════════════════════════════════════════════════════════════════

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  final ResponsiveHelper r;

  // OPTIMIZATION: Cache GoogleFonts base → static final
  static final TextStyle _comicNueBase = GoogleFonts.comicNeue(
    fontWeight: FontWeight.bold,
  );

  const _ErrorView({required this.onRetry, required this.r});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          RepaintBoundary(
            child: Lottie.asset(
              'assets/animations/error.json',
              // RESPONSIVENESS: Responsive width
              width: r.size(150),
              repeat: false,
              frameRate: FrameRate.max,
              errorBuilder: (c, e, s) => const Icon(
                Icons.error_outline,
                size: 60,
                color: Colors.red,
              ),
            ),
          ),
          SizedBox(height: r.spacing(16)),
          Text(
            "Gagal memuat data",
            style: _comicNueBase.copyWith(
              // RESPONSIVENESS: Responsive font
              fontSize: r.font(18),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
                foregroundColor: Colors.orange),
            child: const Text("Coba Lagi"),
          ),
        ],
      ),
    );
  }
}