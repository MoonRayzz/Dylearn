// ignore_for_file: deprecated_member_use, curly_braces_in_flow_control_structures, unnecessary_underscores, use_build_context_synchronously, avoid_init_to_null

import 'dart:io';
import 'package:dylearn/core/services/auth_service.dart';
import 'package:dylearn/core/services/tutorial_service.dart';
import 'package:dylearn/core/utils/responsive_helper.dart';
import 'package:dylearn/features/auth/auth_wrapper.dart';
import 'package:dylearn/shared/providers/settings_provider.dart';
import 'package:dylearn/shared/widgets/background_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:showcaseview/showcaseview.dart';

typedef _VoiceList = List<Map<String, String>>;

// Label pendek untuk dropdown dyslexia — value Firestore tidak berubah
const Map<String, String> _dyslexiaDisplayLabels = {
  'Belum Tahu':                        'Belum Tahu',
  'Visual (Susah bedain huruf)':       'Visual (Susah bedain huruf)',
  'Auditori (Susah ingat suara huruf)':'Auditori (Susah ingat suara)',
  'Campuran':                          'Campuran',
};

class PengaturanScreen extends StatefulWidget {
  const PengaturanScreen({super.key});
  @override
  State<PengaturanScreen> createState() => _PengaturanScreenState();
}

class _PengaturanScreenState extends State<PengaturanScreen> {
  final FlutterTts  _flutterTts  = FlutterTts();
  final AuthService _authService = AuthService();
  final User?       _currentUser = FirebaseAuth.instance.currentUser;

  final ValueNotifier<_VoiceList> _availableVoicesNotifier = ValueNotifier([]);
  final ValueNotifier<bool>       _isLoadingVoiceNotifier  = ValueNotifier(true);

  bool _isTutorialChecked = false;
  final GlobalKey _voiceSettingsKey  = GlobalKey();
  final GlobalKey _visualSettingsKey = GlobalKey();
  late final Map<GlobalKey, String> _showcaseDescriptions;

  String _displayName  = "Pahlawan Cilik";
  String _age          = "";
  String _gender       = "Laki-laki";
  String _grade        = "SD 1";
  String _dyslexiaType = "Belum Tahu";

  // FIX CRASH: Guard mencegah multiple bottom sheet terbuka sekaligus
  // Root cause crash: 7 tap cepat → 7 showModalBottomSheet → OOM → crash
  bool _isSheetOpen = false;

  static const Color _heroStart = Color(0xFFFF9F1C);
  static const Color _heroEnd   = Color(0xFFFF6B35);
  static const Color _heroDark  = Color(0xFFE65100);

  @override
  void initState() {
    super.initState();
    _initVoices();
    _fetchUserProfile();
    _showcaseDescriptions = {
      _voiceSettingsKey:  'Pilih suara teman membaca ceritamu di sini.',
      _visualSettingsKey: 'Ganti font dan ukuran huruf agar lebih nyaman dibaca.',
    };
  }

  @override
  void dispose() {
    _flutterTts.stop();
    _availableVoicesNotifier.dispose();
    _isLoadingVoiceNotifier.dispose();
    super.dispose();
  }

  Future<void> _fetchUserProfile() async {
    if (_currentUser == null) return;
    _displayName = _currentUser.displayName ?? "Pahlawan Cilik";
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users').doc(_currentUser.uid).get();
      if (doc.exists && mounted) {
        final data = doc.data()!;
        setState(() {
          _displayName  = data['displayName'] ?? _displayName;
          _age          = data['age']?.toString()   ?? "";
          _gender       = data['gender']            ?? "Laki-laki";
          _grade        = data['grade']             ?? "SD 1";
          _dyslexiaType = data['dyslexiaType']      ?? "Belum Tahu";
        });
      }
    } catch (e) {
      debugPrint("Gagal load profil: $e");
    }
  }

  List<Map<String, String>> _processVoices(List<dynamic> rawVoices) {
    final List<Map<String, String>> valid = [];
    for (final voice in rawVoices) {
      Map<String, String> v;
      try { v = Map<String, String>.from((voice as Map).cast<String, String>()); }
      catch (_) { continue; }
      final String locale = (v['locale'] ?? '').toLowerCase();
      final String name   = (v['name']   ?? '').toLowerCase();
      if (!locale.startsWith('id'))       continue;
      if (name.contains('network'))       continue;
      if (v['networkRequired'] == 'true') continue;
      valid.add(v);
    }
    return valid;
  }

  Future<void> _initVoices() async {
    try {
      final voices = await _flutterTts.getVoices;
      if (voices != null) {
        final processed = _processVoices(voices);
        if (mounted) {
          _availableVoicesNotifier.value = processed;
          _isLoadingVoiceNotifier.value  = false;
        }
      }
    } catch (e) {
      debugPrint("Gagal memuat suara: $e");
      if (mounted) _isLoadingVoiceNotifier.value = false;
    }
  }

  void _showEditProfileSheet(ResponsiveHelper r) {
    // FIX CRASH: Tolak panggilan jika sheet sudah terbuka
    if (_isSheetOpen) return;
    _isSheetOpen = true;

    final nameController = TextEditingController(text: _displayName);
    final ageController  = TextEditingController(text: _age);
    String tempGender   = ['Laki-laki','Perempuan'].contains(_gender) ? _gender : 'Laki-laki';
    const gradeList = [
      'SD 1', 'SD 2', 'SD 3', 'SD 4', 'SD 5', 'SD 6',
      'SMP 1', 'SMP 2', 'SMP 3',
      'SMA 1', 'SMA 2', 'SMA 3',
    ];
    String tempGrade = gradeList.contains(_grade) ? _grade : 'SD 1';
    String tempDyslexia = _dyslexiaDisplayLabels.containsKey(_dyslexiaType)
                          ? _dyslexiaType : 'Belum Tahu';
    bool   isLoading    = false;

    final oBorder = OutlineInputBorder(borderRadius: BorderRadius.circular(14));
    final fBorder = OutlineInputBorder(borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _heroStart, width: 2));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => PopScope(
        onPopInvoked: (_) {
          // FIX CRASH: HANYA reset flag di sini.
          // Sebelumnya dispose() dipanggil di sini → controller di-dispose
          // saat sheet masih animating close → StatefulBuilder rebuild dengan
          // controller disposed → crash "used after disposed".
          // Dispose yang benar dilakukan di whenComplete di bawah.
          _isSheetOpen = false;
        },
        child: StatefulBuilder(builder: (ctx, setModal) {
          // State foto lokal di dalam sheet
          File?  pickedPhoto = null;
          final String? currentPhotoUrl = _currentUser?.photoURL;
          final String  initial = _displayName.isNotEmpty
              ? _displayName[0].toUpperCase() : '?';

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              padding: EdgeInsets.fromLTRB(r.spacing(20), r.spacing(8), r.spacing(20), r.spacing(32)),
              decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(child: Container(
                        margin: EdgeInsets.only(top: r.spacing(12), bottom: r.spacing(20)),
                        width: 40, height: 5,
                        decoration: BoxDecoration(color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(10)))),

                    Row(children: [
                      Container(padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                              color: _heroStart.withOpacity(0.1), shape: BoxShape.circle),
                          child: const Icon(Icons.edit_rounded, color: _heroStart, size: 20)),
                      SizedBox(width: r.spacing(10)),
                      Text("Edit Profil Pahlawan",
                          style: GoogleFonts.comicNeue(fontSize: r.font(20),
                              fontWeight: FontWeight.bold, color: _heroDark)),
                    ]),
                    SizedBox(height: r.spacing(20)),

                    // ── Foto Profil ─────────────────────────────────────────
                    Center(
                      child: GestureDetector(
                        onTap: () async {
                          final picker = ImagePicker();
                          final XFile? img = await picker.pickImage(
                              source: ImageSource.gallery, imageQuality: 70);
                          if (img != null) setModal(() => pickedPhoto = File(img.path));
                        },
                        child: Stack(
                          children: [
                            CircleAvatar(
                              radius: r.size(44),
                              backgroundColor: _heroStart.withOpacity(0.15),
                              backgroundImage: pickedPhoto != null
                                  ? FileImage(pickedPhoto) as ImageProvider
                                  : (currentPhotoUrl != null && currentPhotoUrl.isNotEmpty
                                      ? CachedNetworkImageProvider(currentPhotoUrl)
                                      : null),
                              child: (pickedPhoto == null &&
                                      (currentPhotoUrl == null || currentPhotoUrl.isEmpty))
                                  ? Text(initial,
                                      style: GoogleFonts.comicNeue(
                                          fontSize: r.font(32),
                                          fontWeight: FontWeight.bold,
                                          color: _heroStart))
                                  : null,
                            ),
                            Positioned(
                              bottom: 0, right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: _heroStart,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2),
                                ),
                                child: Icon(Icons.camera_alt_rounded,
                                    color: Colors.white, size: r.size(14)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Center(
                      child: Padding(
                        padding: EdgeInsets.only(top: r.spacing(6), bottom: r.spacing(16)),
                        child: Text(
                          pickedPhoto != null ? "Foto baru dipilih ✓" : "Ketuk foto untuk mengganti",
                          style: TextStyle(
                              fontSize: r.font(11),
                              color: pickedPhoto != null ? Colors.green : Colors.grey),
                        ),
                      ),
                    ),

                    _SheetLabel(text: "Nama Panggilan", r: r),
                    TextField(controller: nameController,
                        decoration: InputDecoration(hintText: "Contoh: Budi",
                            prefixIcon: const Icon(Icons.person_rounded, color: _heroStart),
                            border: oBorder, enabledBorder: oBorder, focusedBorder: fBorder)),
                    SizedBox(height: r.spacing(14)),

                    _SheetLabel(text: "Umur", r: r),
                    TextField(controller: ageController, keyboardType: TextInputType.number,
                        decoration: InputDecoration(hintText: "Contoh: 9",
                            prefixIcon: const Icon(Icons.cake_rounded, color: _heroStart),
                            border: oBorder, enabledBorder: oBorder, focusedBorder: fBorder)),
                    SizedBox(height: r.spacing(14)),

                    _SheetLabel(text: "Jenis Kelamin", r: r),
                    DropdownButtonFormField<String>(
                        value: tempGender, isExpanded: true,
                        decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.wc_rounded, color: _heroStart),
                            border: oBorder, enabledBorder: oBorder, focusedBorder: fBorder),
                        items: ['Laki-laki','Perempuan']
                            .map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                        onChanged: (v) => setModal(() => tempGender = v!)),
                    SizedBox(height: r.spacing(14)),

                    _SheetLabel(text: "Kelas Berapa?", r: r),
                    DropdownButtonFormField<String>(
                        value: tempGrade, isExpanded: true,
                        decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.school_rounded, color: _heroStart),
                            border: oBorder, enabledBorder: oBorder, focusedBorder: fBorder),
                        items: gradeList
                            .map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                        onChanged: (v) => setModal(() => tempGrade = v!)),
                    SizedBox(height: r.spacing(14)),

                    _SheetLabel(text: "Tipe Kesulitan Baca", r: r),
                    DropdownButtonFormField<String>(
                        value: tempDyslexia, isExpanded: true,
                        decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.psychology_rounded, color: _heroStart),
                            border: oBorder, enabledBorder: oBorder, focusedBorder: fBorder),
                        items: _dyslexiaDisplayLabels.entries.map((e) =>
                            DropdownMenuItem(value: e.key,
                                child: Text(e.value, overflow: TextOverflow.ellipsis))).toList(),
                        onChanged: (v) => setModal(() => tempDyslexia = v!)),
                    SizedBox(height: r.spacing(28)),

                    SizedBox(
                      width: double.infinity, height: r.size(52),
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: _heroStart, foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 0),
                        icon: isLoading
                            ? const SizedBox(width: 18, height: 18,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.check_rounded),
                        label: Text(isLoading ? "Menyimpan..." : "Simpan Perubahan",
                            style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: r.font(14))),
                        onPressed: isLoading ? null : () async {
                          final newName = nameController.text.trim();
                          if (newName.isEmpty) return;
                          setModal(() => isLoading = true);
                          try {
                            // Upload foto baru jika ada
                            String? newPhotoUrl;
                            if (pickedPhoto != null && _currentUser != null) {
                              final ref = FirebaseStorage.instance
                                  .ref()
                                  .child('profile_images/${_currentUser.uid}.jpg');
                              await ref.putFile(pickedPhoto!);
                              newPhotoUrl = await ref.getDownloadURL();
                              await _currentUser.updatePhotoURL(newPhotoUrl);
                            }

                            await _currentUser?.updateDisplayName(newName);
                            final Map<String, dynamic> firestoreData = {
                              'displayName': newName,
                              'age':         int.tryParse(ageController.text) ?? 0,
                              'gender':      tempGender,
                              'grade':       tempGrade,
                              'dyslexiaType':tempDyslexia,
                            };
                            if (newPhotoUrl != null) {
                              firestoreData['photoUrl'] = newPhotoUrl;
                            }
                            await FirebaseFirestore.instance
                                .collection('users')
                                .doc(_currentUser!.uid)
                                .set(firestoreData, SetOptions(merge: true));

                            // reload agar userChanges() trigger update foto di homescreen
                            await _currentUser.reload();

                            if (mounted) {
                              setState(() {
                                _displayName  = newName;
                                _age          = ageController.text;
                                _gender       = tempGender;
                                _grade        = tempGrade;
                                _dyslexiaType = tempDyslexia;
                              });
                              _isSheetOpen = false;
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                  content: Text("Yey! Profil berhasil disimpan! 🎉"),
                                  backgroundColor: Colors.green,
                                  behavior: SnackBarBehavior.floating));
                            }
                          } catch (e) {
                            setModal(() => isLoading = false);
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text("Gagal: $e"), backgroundColor: Colors.red));
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    ).whenComplete(() {
      // FIX CRASH: Dispose controller SETELAH sheet selesai animasi close.
      // Ini titik aman karena widget sudah out of tree sepenuhnya.
      _isSheetOpen = false;
      nameController.dispose();
      ageController.dispose();
    });
  }

  Future<void> _showSyncDialog() async {
    final codeController     = TextEditingController();
    final isFetchingNotifier = ValueNotifier(false);
    await showDialog(
      context: context, barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Tautkan Akun Guru",
            style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2E3192))),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text("Masukkan kode dari Guru kamu untuk menyalin semua riwayat belajar.",
              style: TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 16),
          TextField(controller: codeController,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(hintText: "Contoh: DYL-X9B2A1",
                  prefixIcon: const Icon(Icons.password_rounded),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
        ]),
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: isFetchingNotifier,
            builder: (_, isFetching, __) {
              if (isFetching) return const Padding(
                  padding: EdgeInsets.only(right: 16, bottom: 8),
                  child: CircularProgressIndicator(color: Colors.orange));
              return Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(onPressed: () => Navigator.pop(dialogCtx),
                    child: const Text("Batal", style: TextStyle(color: Colors.grey))),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E3192),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  onPressed: () async {
                    final code = codeController.text.trim();
                    if (code.isEmpty) return;
                    isFetchingNotifier.value = true;
                    try {
                      final preview = await _authService.fetchSyncPreview(code);
                      if (!mounted) return;
                      Navigator.pop(dialogCtx);
                      await _showSyncConfirmDialog(preview);
                    } catch (e) {
                      isFetchingNotifier.value = false;
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(e.toString().replaceAll('Exception:', '').trim()),
                          backgroundColor: Colors.red, behavior: SnackBarBehavior.floating));
                    }
                  },
                  child: const Text("Cari Kode", style: TextStyle(color: Colors.white)),
                ),
              ]);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _showSyncConfirmDialog(SyncPreviewData preview) async {
    bool useTeacherProfile = false;
    if (preview.hasProfileDiff) {
      final choice = await showDialog<bool>(context: context, barrierDismissible: false,
          builder: (_) => _SyncProfileChoiceDialog(preview: preview));
      if (choice == null) return;
      useTeacherProfile = choice;
    }
    if (!mounted) return;
    showDialog(context: context, barrierDismissible: false,
        builder: (_) => const PopScope(canPop: false,
            child: AlertDialog(content: Padding(padding: EdgeInsets.all(8),
                child: Row(children: [
                  CircularProgressIndicator(color: Color(0xFF2E3192)),
                  SizedBox(width: 20),
                  Expanded(child: Text("Sedang menyalin data...", style: TextStyle(fontSize: 14))),
                ])))));
    try {
      await _authService.executeSyncStudent(
          preview: preview, useTeacherProfile: useTeacherProfile);
      if (!mounted) return;
      Navigator.pop(context);
      await _fetchUserProfile();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Sukses! ${preview.totalBooks} buku & data latihan disalin! 🚀"),
          backgroundColor: Colors.green, behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4)));
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceAll('Exception:', '').trim()),
          backgroundColor: Colors.red, behavior: SnackBarBehavior.floating));
    }
  }

  Future<void> _handleLogout(bool revokeConsent) async {
    final confirm = await showDialog<bool>(context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(revokeConsent ? "Tarik Persetujuan?" : "Keluar Akun?"),
          content: Text(revokeConsent
              ? "Akun akan dikeluarkan dan data izin riset akan direset."
              : "Kamu harus login lagi nanti untuk membaca."),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false),
                child: const Text("Batal")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: revokeConsent ? Colors.red : Colors.orange),
              onPressed: () => Navigator.pop(context, true),
              child: Text(revokeConsent ? "Hapus" : "Keluar",
                  style: const TextStyle(color: Colors.white))),
          ],
        ));
    if (confirm != true) return;
    final navigator = Navigator.of(context);
    navigator.pushAndRemoveUntil(
        PageRouteBuilder(
            pageBuilder: (_, __, ___) => const Scaffold(
                backgroundColor: Colors.white,
                body: Center(child: CircularProgressIndicator(color: Colors.orange))),
            transitionDuration: Duration.zero),
        (_) => false);
    if (revokeConsent) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('has_consented', false);
    }
    await _authService.signOut();
    navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthWrapper()), (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final ResponsiveHelper r = context.r;
    final TextStyle tooltipStyle = TextStyle(
        fontFamily: context.read<SettingsProvider>().fontFamily,
        fontSize: r.font(14), color: Colors.black87, height: 1.4);

    return ShowCaseWidget(
      onStart: (_, key) {
        final text = _showcaseDescriptions[key];
        if (text != null) TutorialService.speakShowcaseText(text);
      },
      onComplete: (_, key) => TutorialService.stopSpeaking(),
      onFinish:   () => TutorialService.stopSpeaking(),
      builder: (showcaseCtx) {
        if (!_isTutorialChecked) {
          _isTutorialChecked = true;
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            final hasSeen = await TutorialService.hasSeenTutorial('pengaturan');
            if (!hasSeen && mounted) {
              ShowCaseWidget.of(showcaseCtx).startShowCase(
                  [_voiceSettingsKey, _visualSettingsKey]);
              await TutorialService.markTutorialAsSeen('pengaturan');
            }
          });
        }

        return Scaffold(
          backgroundColor: const Color(0xFFF5F7FA),
          body: BackgroundWrapper(
            showBottomBlob: false,
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverAppBar(
                  expandedHeight: r.size(200),
                  pinned: true,
                  backgroundColor: _heroStart,
                  elevation: 0,
                  flexibleSpace: FlexibleSpaceBar(
                    background: _HeroProfileBanner(
                      displayName: _displayName, grade: _grade, age: _age,
                      gender: _gender, dyslexiaType: _dyslexiaType,
                      onEditTap: () => _showEditProfileSheet(r), r: r),
                  ),
                  leading: IconButton(
                    icon: Container(padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.25), shape: BoxShape.circle),
                        child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 18)),
                    onPressed: () => Navigator.maybePop(context)),
                  title: const Text("Pengaturan",
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ),

                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                      r.spacing(16), r.spacing(20), r.spacing(16), r.spacing(100)),
                  sliver: SliverList(delegate: SliverChildListDelegate([
                    Showcase(key: _voiceSettingsKey,
                        description: _showcaseDescriptions[_voiceSettingsKey]!,
                        descTextStyle: tooltipStyle,
                        child: _VoiceSettingsSection(
                            flutterTts: _flutterTts,
                            availableVoicesNotifier: _availableVoicesNotifier,
                            isLoadingNotifier: _isLoadingVoiceNotifier, r: r)),
                    SizedBox(height: r.spacing(16)),

                    Showcase(key: _visualSettingsKey,
                        description: _showcaseDescriptions[_visualSettingsKey]!,
                        descTextStyle: tooltipStyle,
                        child: _VisualSettingsSection(r: r)),
                    SizedBox(height: r.spacing(16)),

                    _buildAccountActions(r),
                    SizedBox(height: r.spacing(24)),

                    Center(child: Text("Versi Aplikasi 1.0.0",
                        style: TextStyle(color: Colors.grey.shade400, fontSize: r.font(11)))),
                  ])),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAccountActions(ResponsiveHelper r) {
    return _SettingsCard(title: "Akun", icon: Icons.manage_accounts_rounded,
        color: Colors.purple, r: r,
        child: Column(children: [
          _ActionTile(icon: Icons.sync_rounded, color: Colors.purple,
              title: "Tautkan Akun Guru", subtitle: "Salin data dari tugas gurumu",
              onTap: _showSyncDialog, r: r),
          _Divider(),
          _ActionTile(icon: Icons.refresh_rounded, color: Colors.orange,
              title: "Reset Izin Orang Tua", subtitle: "Hapus data persetujuan",
              onTap: () => _handleLogout(true), r: r),
          _Divider(),
          _ActionTile(icon: Icons.logout_rounded, color: Colors.red,
              title: "Keluar Aplikasi", onTap: () => _handleLogout(false),
              isDestructive: true, r: r),
        ]));
  }
}

// ════════════════════════════════════════════════════════════════════════════
class _HeroProfileBanner extends StatelessWidget {
  final String displayName, grade, age, gender, dyslexiaType;
  final VoidCallback onEditTap;
  final ResponsiveHelper r;

  static const Color _heroStart = Color(0xFFFF9F1C);
  static const Color _heroEnd   = Color(0xFFFF6B35);

  const _HeroProfileBanner({
    required this.displayName, required this.grade, required this.age,
    required this.gender, required this.dyslexiaType,
    required this.onEditTap, required this.r});

  @override
  Widget build(BuildContext context) {
    final String initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
    return Container(
      decoration: const BoxDecoration(gradient: LinearGradient(
          colors: [_heroStart, _heroEnd], begin: Alignment.topLeft, end: Alignment.bottomRight)),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(r.spacing(20), r.spacing(48), r.spacing(20), r.spacing(16)),
          child: Row(children: [
            Container(width: r.size(70), height: r.size(70),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.25),
                    shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3)),
                child: Center(child: Text(initial,
                    style: GoogleFonts.comicNeue(fontSize: r.font(30),
                        fontWeight: FontWeight.bold, color: Colors.white)))),
            SizedBox(width: r.spacing(14)),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(displayName, overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.comicNeue(fontSize: r.font(20),
                          fontWeight: FontWeight.bold, color: Colors.white)),
                  SizedBox(height: r.spacing(6)),
                  Wrap(spacing: r.spacing(6), runSpacing: r.spacing(4), children: [
                    if (grade.isNotEmpty && grade != '-')
                      _HeroChip(text: grade, icon: Icons.school_rounded),
                    if (age.isNotEmpty && age != '0')
                      _HeroChip(text: "$age thn", icon: Icons.cake_rounded),
                    if (gender.isNotEmpty && gender != '-')
                      _HeroChip(text: gender == 'Laki-laki' ? '♂ L' : '♀ P',
                          icon: Icons.person_rounded),
                  ]),
                ])),
            GestureDetector(onTap: onEditTap,
                child: Container(padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.edit_rounded, color: Colors.white, size: 18))),
          ]),
        ),
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  final String text; final IconData icon;
  const _HeroChip({required this.text, required this.icon});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.25),
          borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 10, color: Colors.white), const SizedBox(width: 4),
        Text(text, style: GoogleFonts.poppins(
            fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
      ]));
  }
}

// ════════════════════════════════════════════════════════════════════════════
class _SettingsCard extends StatelessWidget {
  final String title; final IconData icon; final Color color;
  final Widget child; final ResponsiveHelper r;
  const _SettingsCard({required this.title, required this.icon,
      required this.color, required this.child, required this.r});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 4))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: r.spacing(16), vertical: r.spacing(12)),
          decoration: BoxDecoration(color: color.withOpacity(0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
          child: Row(children: [
            Container(padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, color: color, size: r.size(16))),
            SizedBox(width: r.spacing(10)),
            Text(title, style: TextStyle(fontSize: r.font(15),
                fontWeight: FontWeight.bold, color: color)),
          ])),
        Padding(padding: EdgeInsets.all(r.spacing(16)), child: child),
      ]));
  }
}

// ════════════════════════════════════════════════════════════════════════════
class _VoiceSettingsSection extends StatelessWidget {
  final FlutterTts flutterTts;
  final ValueNotifier<_VoiceList> availableVoicesNotifier;
  final ValueNotifier<bool> isLoadingNotifier;
  final ResponsiveHelper r;
  static const Color _c = Color(0xFF2EC4B6);
  static final ButtonStyle _style = ElevatedButton.styleFrom(
      backgroundColor: _c, foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0);

  const _VoiceSettingsSection({required this.flutterTts,
      required this.availableVoicesNotifier, required this.isLoadingNotifier, required this.r});

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(title: "Suara & Bicara", icon: Icons.record_voice_over_rounded,
        color: _c, r: r,
        child: Consumer<SettingsProvider>(builder: (_, s, __) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Pilih Karakter Suara:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: r.font(13))),
            SizedBox(height: r.spacing(8)),
            _VoiceDropdown(availableVoicesNotifier: availableVoicesNotifier,
                isLoadingNotifier: isLoadingNotifier, settings: s, r: r),
            SizedBox(height: r.spacing(16)),
            _SliderControl(label: "Kecepatan Bicara", value: s.ttsRate, min: 0.1, max: 1.0,
                leftLabel: "Pelan", rightLabel: "Cepat", accentColor: _c,
                onChanged: s.updateTtsRate, onChangeEnd: (v) => flutterTts.setSpeechRate(v), r: r),
            _SliderControl(label: "Nada Suara", value: s.ttsPitch, min: 0.5, max: 2.0,
                leftLabel: "Rendah", rightLabel: "Tinggi", accentColor: _c,
                onChanged: s.updateTtsPitch, onChangeEnd: (v) => flutterTts.setPitch(v), r: r),
            SizedBox(height: r.spacing(12)),
            SizedBox(width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.play_circle_fill_rounded),
                  label: const Text("Cek Suara Sekarang"), style: _style,
                  onPressed: () async {
                    await flutterTts.stop();
                    await flutterTts.setSpeechRate(s.ttsRate);
                    await flutterTts.setPitch(s.ttsPitch);
                    if (s.selectedVoice != null) await flutterTts.setVoice(
                        {"name": s.selectedVoice!["name"]!, "locale": s.selectedVoice!["locale"]!});
                    await flutterTts.speak("Halo, ini contoh suara saya.");
                  },
                )),
          ],
        )));
  }
}

// ════════════════════════════════════════════════════════════════════════════
class _VisualSettingsSection extends StatelessWidget {
  final ResponsiveHelper r;
  static const Color _c = Color(0xFF0984E3);
  static final BoxDecoration _previewDec = BoxDecoration(
      color: Colors.orange.shade50, borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.orange.shade200));
  static final BoxDecoration _dropDec = BoxDecoration(
      color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.grey.shade200));
  const _VisualSettingsSection({required this.r});

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(title: "Tampilan Teks", icon: Icons.text_fields_rounded, color: _c, r: r,
        child: Consumer<SettingsProvider>(builder: (_, s, __) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Gaya Huruf (Font)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: r.font(13))),
            SizedBox(height: r.spacing(8)),
            Container(padding: EdgeInsets.symmetric(horizontal: r.spacing(12)), decoration: _dropDec,
                child: DropdownButtonHideUnderline(child: DropdownButton<String>(
                    isExpanded: true, value: s.fontFamily,
                    items: const [
                      DropdownMenuItem(value: 'OpenDyslexic', child: Text('OpenDyslexic', style: TextStyle(fontFamily: 'OpenDyslexic'))),
                      DropdownMenuItem(value: 'TrikaIndoDyslexic3', child: Text('TrikaIndoDyslexic', style: TextStyle(fontFamily: 'TrikaIndoDyslexic3'))),
                    ],
                    onChanged: (v) { if (v != null) Future.microtask(() => s.updateFontFamily(v)); }))),
            SizedBox(height: r.spacing(12)),
            AnimatedSwitcher(duration: const Duration(milliseconds: 200),
                child: Container(key: ValueKey(s.fontFamily), width: double.infinity,
                    padding: EdgeInsets.symmetric(horizontal: r.spacing(14), vertical: r.spacing(10)),
                    decoration: _previewDec,
                    child: Text('"Aku suka membaca cerita seru!"',
                        style: TextStyle(fontFamily: s.fontFamily, fontSize: r.font(14), color: Colors.orange.shade800)))),
            SizedBox(height: r.spacing(16)), const Divider(), SizedBox(height: r.spacing(12)),
            Text("Ukuran Huruf", style: TextStyle(fontWeight: FontWeight.bold, fontSize: r.font(13))),
            _SliderControl(label: "", value: s.textScaleFactor.clamp(0.8, 1.1),
                min: 0.8, max: 1.1, accentColor: _c, onChanged: s.updateTextScale, r: r,
                customChild: Row(children: [
                  const Text("A", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  Expanded(child: SliderTheme(data: _SliderControl._st, child: Slider(
                      value: s.textScaleFactor.clamp(0.8, 1.1), min: 0.8, max: 1.1, divisions: 3,
                      activeColor: _c, label: "${(s.textScaleFactor * 100).round()}%",
                      onChanged: s.updateTextScale))),
                  const Text("A", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                ])),
            const Divider(), SizedBox(height: r.spacing(8)),
            Text("Jarak Antar Huruf", style: TextStyle(fontWeight: FontWeight.bold, fontSize: r.font(13))),
            _SliderControl(label: "", value: s.letterSpacing, min: 0.0, max: 4.0,
                accentColor: _c, onChanged: s.updateLetterSpacing, r: r,
                customChild: Row(children: [
                  Text("Rapat", style: TextStyle(fontSize: r.font(11), fontWeight: FontWeight.bold)),
                  Expanded(child: SliderTheme(data: _SliderControl._st, child: Slider(
                      value: s.letterSpacing, min: 0.0, max: 4.0, divisions: 8,
                      activeColor: _c, label: s.letterSpacing.toStringAsFixed(1),
                      onChanged: s.updateLetterSpacing))),
                  Text("Renggang", style: TextStyle(fontSize: r.font(11), fontWeight: FontWeight.bold)),
                ])),
            const Divider(), SizedBox(height: r.spacing(8)),
            Text("Jarak Antar Baris", style: TextStyle(fontWeight: FontWeight.bold, fontSize: r.font(13))),
            _SliderControl(label: "", value: s.lineHeight, min: 1.2, max: 2.4,
                accentColor: _c, onChanged: s.updateLineHeight, r: r,
                customChild: Row(children: [
                  Text("Rapat", style: TextStyle(fontSize: r.font(11), fontWeight: FontWeight.bold)),
                  Expanded(child: SliderTheme(data: _SliderControl._st, child: Slider(
                      value: s.lineHeight, min: 1.2, max: 2.4, divisions: 6,
                      activeColor: _c, label: s.lineHeight.toStringAsFixed(1),
                      onChanged: s.updateLineHeight))),
                  Text("Lebar", style: TextStyle(fontSize: r.font(11), fontWeight: FontWeight.bold)),
                ])),
          ],
        )));
  }
}

// ════════════════════════════════════════════════════════════════════════════
class _VoiceDropdown extends StatelessWidget {
  final ValueNotifier<_VoiceList> availableVoicesNotifier;
  final ValueNotifier<bool> isLoadingNotifier;
  final SettingsProvider settings;
  final ResponsiveHelper r;
  static final BoxDecoration _dec = BoxDecoration(
      color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.grey.shade200));
  const _VoiceDropdown({required this.availableVoicesNotifier,
      required this.isLoadingNotifier, required this.settings, required this.r});

  String _name(Map<String, String> v, int i) {
    final n = (v['name'] ?? '').toLowerCase();
    if (n.contains('idf') || n.contains('female')) return "Indonesia — Suara Perempuan";
    if (n.contains('idm') || n.contains('male'))   return "Indonesia — Suara Laki-laki";
    if (i == 0) return "Indonesia — Utama";
    return "Indonesia — Varian ${i + 1}";
  }

  @override
  Widget build(BuildContext context) {
    return Container(padding: EdgeInsets.symmetric(horizontal: r.spacing(12)), decoration: _dec,
        child: ValueListenableBuilder<bool>(valueListenable: isLoadingNotifier,
            builder: (_, loading, __) => ValueListenableBuilder<_VoiceList>(
                valueListenable: availableVoicesNotifier,
                builder: (_, voices, __) {
                  if (loading) return Padding(padding: EdgeInsets.all(r.spacing(12)),
                      child: const LinearProgressIndicator());
                  Map<String, String>? cur;
                  if (settings.selectedVoice != null && voices.isNotEmpty) {
                    try { cur = voices.firstWhere((v) =>
                        v['name'] == settings.selectedVoice!['name'] &&
                        v['locale'] == settings.selectedVoice!['locale']); } catch (_) {}
                  }
                  return DropdownButtonHideUnderline(child: DropdownButton<Map<String, String>>(
                      isExpanded: true, hint: const Text("Pilih Suara..."), value: cur,
                      items: voices.asMap().entries.map((e) => DropdownMenuItem<Map<String, String>>(
                          value: e.value, child: Text(_name(e.value, e.key),
                              style: TextStyle(fontSize: r.font(13))))).toList(),
                      onChanged: (v) { if (v != null) settings.updateTtsVoice(v); }));
                })));
  }
}

// ════════════════════════════════════════════════════════════════════════════
class _SliderControl extends StatelessWidget {
  final String label; final double value, min, max;
  final String? leftLabel, rightLabel; final Color accentColor;
  final Function(double) onChanged; final Function(double)? onChangeEnd;
  final ResponsiveHelper r; final Widget? customChild;
  static const SliderThemeData _st = SliderThemeData(
      trackHeight: 6, thumbShape: RoundSliderThumbShape(enabledThumbRadius: 8));
  const _SliderControl({required this.label, required this.value,
      required this.min, required this.max, required this.accentColor,
      required this.onChanged, required this.r,
      this.onChangeEnd, this.leftLabel, this.rightLabel, this.customChild});

  @override
  Widget build(BuildContext context) {
    if (customChild != null) return customChild!;
    return Column(children: [
      if (label.isNotEmpty) Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: TextStyle(fontSize: r.font(13))),
        Text("${value.toStringAsFixed(1)}×",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: r.font(12), color: accentColor)),
      ]),
      Row(children: [
        if (leftLabel != null) Text(leftLabel!, style: TextStyle(fontSize: r.font(11), color: Colors.grey)),
        Expanded(child: SliderTheme(data: _st, child: Slider(
            value: value, min: min, max: max, divisions: 10,
            activeColor: accentColor, inactiveColor: Colors.grey.shade200,
            onChanged: onChanged, onChangeEnd: onChangeEnd))),
        if (rightLabel != null) Text(rightLabel!, style: TextStyle(fontSize: r.font(11), color: Colors.grey)),
      ]),
    ]);
  }
}

// ════════════════════════════════════════════════════════════════════════════
class _ActionTile extends StatelessWidget {
  final IconData icon; final Color color; final String title;
  final String? subtitle; final VoidCallback onTap;
  final bool isDestructive; final ResponsiveHelper r;
  const _ActionTile({required this.icon, required this.color,
      required this.title, required this.onTap, required this.r,
      this.subtitle, this.isDestructive = false});

  @override
  Widget build(BuildContext context) {
    return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(12),
        child: Padding(padding: EdgeInsets.symmetric(vertical: r.spacing(12), horizontal: r.spacing(4)),
            child: Row(children: [
              Container(padding: EdgeInsets.all(r.spacing(8)),
                  decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
                  child: Icon(icon, color: color, size: r.size(20))),
              SizedBox(width: r.spacing(14)),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: r.font(13),
                    color: isDestructive ? Colors.red : Colors.black87)),
                if (subtitle != null) Text(subtitle!,
                    style: TextStyle(fontSize: r.font(11), color: Colors.grey)),
              ])),
              Icon(Icons.chevron_right_rounded, color: Colors.grey.shade300),
            ])));
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, indent: 46, endIndent: 0, color: Colors.grey.shade100);
}

class _SheetLabel extends StatelessWidget {
  final String text; final ResponsiveHelper r;
  const _SheetLabel({required this.text, required this.r});
  @override
  Widget build(BuildContext context) {
    return Padding(padding: EdgeInsets.only(bottom: r.spacing(6)),
        child: Text(text, style: TextStyle(fontWeight: FontWeight.w600,
            fontSize: r.font(12), color: Colors.grey.shade600)));
  }
}

// ════════════════════════════════════════════════════════════════════════════
class _SyncProfileChoiceDialog extends StatefulWidget {
  final SyncPreviewData preview;
  const _SyncProfileChoiceDialog({required this.preview});
  @override
  State<_SyncProfileChoiceDialog> createState() => _SyncProfileChoiceDialogState();
}

class _SyncProfileChoiceDialogState extends State<_SyncProfileChoiceDialog> {
  bool _useTeacherProfile = false;
  static const Color _pc = Color(0xFF2E3192);
  static const Color _tc = Color(0xFF1565C0);
  static const Color _sc = Color(0xFFE65100);

  @override
  Widget build(BuildContext context) {
    final p = widget.preview;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: SingleChildScrollView(padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.compare_arrows_rounded, color: _pc, size: 24), const SizedBox(width: 10),
              Expanded(child: Text("Ada Perbedaan Data Profil",
                  style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16, color: _pc))),
            ]),
            const SizedBox(height: 8),
            Text("Pilih profil mana yang ingin kamu pakai:",
                style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 16),
            Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.green.shade200)),
                child: Row(children: [
                  const Icon(Icons.library_books_rounded, color: Colors.green, size: 18), const SizedBox(width: 10),
                  Expanded(child: Text("${p.totalBooks} buku & semua riwayat latihan akan disalin.",
                      style: GoogleFonts.poppins(fontSize: 12, color: Colors.green.shade800))),
                ])),
            const SizedBox(height: 16),
            _buildCompareTable(p), const SizedBox(height: 16),
            _buildRadioChoice(value: false, title: "Pakai Profil Saya Sendiri",
                subtitle: p.currentName, color: _sc, icon: Icons.person_rounded),
            const SizedBox(height: 10),
            _buildRadioChoice(value: true, title: "Pakai Profil dari Guru",
                subtitle: p.managedName, color: _tc, icon: Icons.school_rounded),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, null),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: Text("Batal", style: GoogleFonts.poppins(color: Colors.grey)))),
              const SizedBox(width: 12),
              Expanded(flex: 2, child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, _useTeacherProfile),
                  style: ElevatedButton.styleFrom(backgroundColor: _pc,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: Text("Konfirmasi & Sinkronisasi",
                      style: GoogleFonts.poppins(color: Colors.white,
                          fontWeight: FontWeight.bold, fontSize: 13)))),
            ]),
          ])));
  }

  Widget _buildRadioChoice({required bool value, required String title,
      required String subtitle, required Color color, required IconData icon}) {
    final bool sel = _useTeacherProfile == value;
    return GestureDetector(onTap: () => setState(() => _useTeacherProfile = value),
        child: AnimatedContainer(duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: sel ? color.withOpacity(0.08) : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: sel ? color : Colors.grey.shade300, width: sel ? 2 : 1)),
            child: Row(children: [
              Container(padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
                  child: Icon(icon, color: color, size: 20)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 13,
                    color: sel ? color : Colors.black87)),
                Text(subtitle, style: GoogleFonts.poppins(fontSize: 11, color: Colors.grey),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),
              Radio<bool>(value: value, groupValue: _useTeacherProfile, activeColor: color,
                  onChanged: (v) { if (v != null) setState(() => _useTeacherProfile = v); }),
            ])));
  }

  Widget _buildCompareTable(SyncPreviewData p) {
    final rows = <Map<String, String>>[
      if (p.managedName         != p.currentName)        {'label':'Nama', 'guru':p.managedName,       'kamu':p.currentName},
      if (p.managedAge          != p.currentAge)         {'label':'Umur', 'guru':'${p.managedAge} thn','kamu':'${p.currentAge} thn'},
      if (p.managedGender       != p.currentGender)      {'label':'Gender','guru':p.managedGender,    'kamu':p.currentGender},
      if (p.managedGrade        != p.currentGrade)       {'label':'Kelas','guru':p.managedGrade,       'kamu':p.currentGrade},
      if (p.managedDyslexiaType != p.currentDyslexiaType){'label':'Tipe', 'guru':p.managedDyslexiaType,'kamu':p.currentDyslexiaType},
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    return Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200)),
        child: Column(children: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: Colors.grey.shade100,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12))),
              child: Row(children: [
                const Expanded(flex: 2, child: Text('')),
                Expanded(flex: 3, child: Text('Profil Guru', textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 11, color: _tc))),
                Expanded(flex: 3, child: Text('Profil Kamu', textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 11, color: _sc))),
              ])),
          ...rows.asMap().entries.map((entry) {
            final isLast = entry.key == rows.length - 1;
            final row = entry.value;
            return Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(border: isLast ? null
                    : Border(bottom: BorderSide(color: Colors.grey.shade200))),
                child: Row(children: [
                  Expanded(flex: 2, child: Text(row['label']!, style: GoogleFonts.poppins(
                      fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600))),
                  Expanded(flex: 3, child: Text(row['guru']!, textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(fontSize: 11, color: _tc, fontWeight: FontWeight.bold),
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
                  Expanded(flex: 3, child: Text(row['kamu']!, textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(fontSize: 11, color: _sc, fontWeight: FontWeight.bold),
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
                ]));
          }),
        ]));
  }
}