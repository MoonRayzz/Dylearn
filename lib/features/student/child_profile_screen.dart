// ignore_for_file: deprecated_member_use, use_build_context_synchronously, curly_braces_in_flow_control_structures

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/utils/responsive_helper.dart';

class ChildProfileScreen extends StatefulWidget {
  final bool isEditMode;
  const ChildProfileScreen({super.key, this.isEditMode = false});

  @override
  State<ChildProfileScreen> createState() =>
      _ChildProfileScreenState();
}

class _ChildProfileScreenState extends State<ChildProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _ageController;

  static const List<String> _gradeOptions = [
    'SD 1', 'SD 2', 'SD 3', 'SD 4', 'SD 5', 'SD 6',
    'SMP 1', 'SMP 2', 'SMP 3',
    'SMA 1', 'SMA 2', 'SMA 3',
  ];
  static const List<String> _dyslexiaOptions = [
    'Belum Tahu', 'Ringan', 'Sedang', 'Berat'
  ];

  // OPTIMIZATION #3: Cache DropdownMenuItem list → static final
  // Eliminasi .map().toList() yang membuat list baru setiap build()
  static final List<DropdownMenuItem<String>> _genderItems = const [
    DropdownMenuItem(value: 'L', child: Text("Laki-laki")),
    DropdownMenuItem(value: 'P', child: Text("Perempuan")),
  ];

  static final List<DropdownMenuItem<String>> _gradeItems =
      _gradeOptions
          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
          .toList();

  static final List<DropdownMenuItem<String>> _dyslexiaItems =
      _dyslexiaOptions
          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
          .toList();

  // OPTIMIZATION #6: Cache borderStyle → static const field
  static const InputBorder _borderStyle = OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(12)),
  );

  // OPTIMIZATION #4: Cache ButtonStyle → static final
  static final ButtonStyle _saveButtonStyle =
      ElevatedButton.styleFrom(
    backgroundColor: Colors.orange,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
    ),
    elevation: 2,
  );

  // OPTIMIZATION #5: Cache GoogleFonts → static final
  // Eliminasi font lookup setiap build()
  // Tidak bisa pakai r.font() karena static — font size responsive
  // akan diterapkan di build() dengan copyWith
  static final TextStyle _titleBaseStyle = GoogleFonts.comicNeue(
    fontWeight: FontWeight.bold,
  );

  // OPTIMIZATION #5: Cache button text style base
  static const TextStyle _buttonTextStyle = TextStyle(
    color: Colors.white,
    fontWeight: FontWeight.bold,
  );

  String _selectedGender = 'L';
  String _selectedGrade = 'SD 1';
  String _selectedDyslexia = 'Belum Tahu';

  // OPTIMIZATION #2: Ganti _isLoading bool + setState
  // → ValueNotifier untuk isolasi rebuild hanya pada button
  final ValueNotifier<bool> _isLoadingNotifier =
      ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _ageController = TextEditingController();
    _loadUserData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    // OPTIMIZATION #2: Dispose ValueNotifier
    _isLoadingNotifier.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // BUG FIX #4: Guard mounted lebih awal sebelum akses controller
    if (!mounted) return;

    if (_nameController.text.isEmpty &&
        user.displayName != null) {
      _nameController.text = user.displayName!;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!mounted) return;

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;

        setState(() {
          if (data.containsKey('displayName')) {
            _nameController.text = data['displayName'] ?? '';
          }
          if (data.containsKey('age')) {
            _ageController.text =
                (data['age'] ?? '').toString();
          }

          final String dbGender = data['gender'] ?? 'L';
          _selectedGender =
              (dbGender == 'L' || dbGender == 'P')
                  ? dbGender
                  : 'L';

          final String dbGrade = data['grade'] ?? 'SD 1';
          _selectedGrade = _gradeOptions.contains(dbGrade)
              ? dbGrade
              : 'SD 1';

          final String dbDyslexia =
              data['dyslexiaType'] ?? 'Belum Tahu';
          _selectedDyslexia =
              _dyslexiaOptions.contains(dbDyslexia)
                  ? dbDyslexia
                  : 'Belum Tahu';
        });
      }
    } catch (e) {
      debugPrint("Error loading profile: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    // RESPONSIVENESS: Ambil helper sekali per build
    final r = context.r;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: widget.isEditMode,
        title: const Text("Data Diri Pengguna"),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        // RESPONSIVENESS: Responsive padding
        padding: EdgeInsets.all(r.spacing(24)),
        physics: const BouncingScrollPhysics(),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Text(
                "Lengkapi datamu untuk mulai bertualang! 🚀",
                textAlign: TextAlign.center,
                // RESPONSIVENESS: Responsive font size via copyWith
                // Base style sudah di-cache sebagai static final
                style: _titleBaseStyle.copyWith(
                  fontSize: r.font(22),
                ),
              ),
              SizedBox(height: r.spacing(20)),

              TextFormField(
                controller: _nameController,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: "Nama Lengkap",
                  helperText:
                      "Nama ini akan dipakai untuk data penelitian",
                  border: _borderStyle,
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (v) =>
                    v!.trim().isEmpty ? "Isi nama dulu ya" : null,
              ),
              SizedBox(height: r.spacing(16)),

              TextFormField(
                controller: _ageController,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: "Umur (Tahun)",
                  border: _borderStyle,
                  prefixIcon: Icon(Icons.cake_outlined),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty)
                    return "Isi umur dulu ya";
                  if (int.tryParse(v) == null)
                    return "Harus angka";
                  return null;
                },
              ),
              SizedBox(height: r.spacing(16)),

              DropdownButtonFormField<String>(
                value: _selectedGender,
                decoration: const InputDecoration(
                  labelText: "Jenis Kelamin",
                  border: _borderStyle,
                  prefixIcon: Icon(Icons.wc),
                ),
                // OPTIMIZATION #3: Gunakan cached items list
                items: _genderItems,
                // BUG FIX #2: Guard null — hindari string "null"
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _selectedGender = v);
                  }
                },
              ),
              SizedBox(height: r.spacing(16)),

              DropdownButtonFormField<String>(
                value: _selectedGrade,
                decoration: const InputDecoration(
                  labelText: "Kelas",
                  border: _borderStyle,
                  prefixIcon: Icon(Icons.school_outlined),
                ),
                // OPTIMIZATION #3: Gunakan cached items list
                items: _gradeItems,
                // BUG FIX #2: Guard null
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _selectedGrade = v);
                  }
                },
              ),
              SizedBox(height: r.spacing(16)),

              DropdownButtonFormField<String>(
                value: _selectedDyslexia,
                decoration: const InputDecoration(
                  labelText: "Kondisi Disleksia (Diagnosa)",
                  border: _borderStyle,
                  prefixIcon:
                      Icon(Icons.medical_information_outlined),
                ),
                // OPTIMIZATION #3: Gunakan cached items list
                items: _dyslexiaItems,
                // BUG FIX #2: Guard null
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _selectedDyslexia = v);
                  }
                },
              ),
              SizedBox(height: r.spacing(30)),

              SizedBox(
                width: double.infinity,
                // RESPONSIVENESS: Responsive button height
                height: r.size(50),
                // OPTIMIZATION #2: ValueListenableBuilder — hanya
                // button yang rebuild saat loading state berubah
                child: ValueListenableBuilder<bool>(
                  valueListenable: _isLoadingNotifier,
                  builder: (context, isLoading, child) {
                    return ElevatedButton(
                      // OPTIMIZATION #4: Gunakan cached ButtonStyle
                      style: _saveButtonStyle,
                      onPressed:
                          isLoading ? null : _saveProfile,
                      child: isLoading
                          ? SizedBox(
                              // RESPONSIVENESS: Responsive spinner
                              height: r.size(20),
                              width: r.size(20),
                              child:
                                  const CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          // RESPONSIVENESS: Responsive button text
                          : Text(
                              "Simpan & Mulai",
                              style: _buttonTextStyle.copyWith(
                                fontSize: r.font(16),
                              ),
                            ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveProfile() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) return;

    // OPTIMIZATION #2: Set notifier — tidak trigger rebuild form
    _isLoadingNotifier.value = true;

    final user = FirebaseAuth.instance.currentUser;

    // BUG FIX #1: Guard user null + early return
    // Jika user null, loading harus di-reset dan tidak lanjut
    if (user == null) {
      _isLoadingNotifier.value = false;
      return;
    }

    try {
      final String finalName = _nameController.text.trim();
      final int finalAge =
          int.tryParse(_ageController.text.trim()) ?? 0;

      final Map<String, dynamic> profileData = {
        'displayName': finalName,
        'age': finalAge,
        'gender': _selectedGender,
        'grade': _selectedGrade,
        'dyslexiaType': _selectedDyslexia,
        'isProfileComplete': true,
        'lastUpdated': FieldValue.serverTimestamp(),
      };

      final List<Future<dynamic>> tasks = [
        FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .set(profileData, SetOptions(merge: true))
      ];

      if (user.displayName != finalName) {
        tasks.add(
          user
              .updateDisplayName(finalName)
              .then((_) => user.reload()),
        );
      }

      await Future.wait(tasks);

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Data berhasil disimpan! 🚀"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Gagal menyimpan: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      // BUG FIX #1: finally memastikan loading SELALU di-reset
      // baik sukses, error, maupun kondisi lain
      if (mounted) _isLoadingNotifier.value = false;
    }
  }
}