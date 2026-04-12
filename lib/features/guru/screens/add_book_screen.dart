// ignore_for_file: use_build_context_synchronously, deprecated_member_use, unnecessary_underscores, curly_braces_in_flow_control_structures

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'package:dylearn/features/page_selection_screen.dart';
import '../../../shared/widgets/system_popup.dart';
import '../../../shared/providers/upload_provider.dart';
import '../../../config/guru_theme.dart';
import '../../../core/utils/responsive_helper.dart';

class AddBookScreen extends StatefulWidget {
  const AddBookScreen({super.key});

  @override
  State<AddBookScreen> createState() => _AddBookScreenState();
}

class _AddBookScreenState extends State<AddBookScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _authorController;

  final ValueNotifier<String>    _selectedCategoryNotifier  = ValueNotifier('Dongeng');
  final ValueNotifier<String>    _selectedSibiLevelNotifier = ValueNotifier("Belum Tahu 🤷‍♂️");
  final ValueNotifier<File?>     _selectedImageNotifier     = ValueNotifier(null);
  final ValueNotifier<File?>     _selectedPdfNotifier       = ValueNotifier(null);
  final ValueNotifier<List<int>> _selectedPagesNotifier     = ValueNotifier([]);

  late final List<DropdownMenuItem<String>> _categoryItems;
  late final List<DropdownMenuItem<String>> _sibiLevelItems;

  bool _isRoleChecking  = true;
  bool _isRoleAuthorized = false;

  @override
  void initState() {
    super.initState();
    _titleController  = TextEditingController();
    _authorController = TextEditingController();

    final itemStyle = GoogleFonts.plusJakartaSans(
        fontSize: 14, color: GuruTheme.onSurface);

    _categoryItems = const ['Dongeng','Legenda','Cerpen','Cerita Rakyat','Mitos']
        .map((v) => DropdownMenuItem(value: v, child: Text(v, style: itemStyle)))
        .toList();

    final Map<String, String> sibiMap = {
      "Belum Tahu 🤷‍♂️": "Belum Tahu",
      "Bintang Kecil ⭐":  "Fase A (Umumnya Kelas 1-2 SD)",
      "Petualang Kata 🎒": "Fase B (Umumnya Kelas 3-4 SD)",
      "Jagoan Baca 🦸‍♂️":   "Fase C (Umumnya Kelas 5-6 SD)",
      "Kapten Cerita ⛵":  "Fase D (Umumnya SMP)",
      "Master Buku 👑":    "Fase E (Umumnya SMA)",
    };

    _sibiLevelItems = sibiMap.entries.map((e) => DropdownMenuItem(
      value: e.key,
      child: Text(e.value, style: itemStyle),
    )).toList();

    WidgetsBinding.instance.addPostFrameCallback((_) => _verifyGuruRole());
  }

  @override
  void dispose() {
    _titleController.dispose();
    _authorController.dispose();
    _selectedCategoryNotifier.dispose();
    _selectedSibiLevelNotifier.dispose();
    _selectedImageNotifier.dispose();
    _selectedPdfNotifier.dispose();
    _selectedPagesNotifier.dispose();
    super.dispose();
  }

  // ── Logic: verifikasi role guru ────────────────────────────────────────────
  Future<void> _verifyGuruRole() async {
    if (!mounted) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) { Navigator.pop(context); return; }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users').doc(user.uid).get();
      if (!mounted) return;
      final role = doc.data()?['role']?.toString() ?? '';
      if (role == 'guru') {
        setState(() { _isRoleChecking = false; _isRoleAuthorized = true; });
      } else {
        setState(() => _isRoleChecking = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Hanya guru yang dapat menambahkan buku ke perpustakaan.'),
          backgroundColor: GuruTheme.errorRed,
          behavior: SnackBarBehavior.floating,
        ));
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) setState(() { _isRoleChecking = false; _isRoleAuthorized = true; });
    }
  }

  // ── Logic: pilih gambar cover ──────────────────────────────────────────────
  Future<void> _pickImage() async {
    final XFile? image = await ImagePicker().pickImage(
        source: ImageSource.gallery, imageQuality: 80);
    if (image != null) _selectedImageNotifier.value = File(image.path);
  }

  // ── Logic: pilih PDF + halaman ─────────────────────────────────────────────
  Future<void> _pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['pdf']);
    if (result == null || result.files.single.path == null) return;

    final pdfFile  = File(result.files.single.path!);
    final fileName = result.files.single.name;
    if (!mounted) return;

    final List<int>? selectedIndices = await Navigator.push<List<int>>(
      context,
      MaterialPageRoute(
        builder: (_) => PageSelectionScreen(
          pdfFile: pdfFile,
          fileHash: fileName,
          isReturningResult: true,
        ),
      ),
    );

    if (selectedIndices != null && selectedIndices.isNotEmpty) {
      _selectedPdfNotifier.value   = pdfFile;
      _selectedPagesNotifier.value = selectedIndices;
    }
  }

  // ── Logic: trigger upload via UploadProvider ───────────────────────────────
  void _triggerUpload() {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      showSystemPopup(
        context: context,
        type: PopupType.warning,
        title: 'Belum Masuk',
        message: 'Kamu harus masuk dulu untuk menyimpan buku.',
        confirmText: 'Oke',
      );
      return;
    }

    if (_selectedImageNotifier.value == null) {
      showSystemPopup(
        context: context,
        type: PopupType.warning,
        title: 'Sampul Belum Ada',
        message: 'Jangan lupa pilih gambar sampul yang bagus untuk bukumu ya!',
        confirmText: 'Oke',
      );
      return;
    }

    if (_selectedPdfNotifier.value == null || _selectedPagesNotifier.value.isEmpty) {
      showSystemPopup(
        context: context,
        type: PopupType.warning,
        title: 'Cerita Belum Ada',
        message: 'Bukumu belum ada ceritanya. Yuk, pilih file PDF-nya!',
        confirmText: 'Oke',
      );
      return;
    }

    final metadata = {
      'title':     _titleController.text.trim(),
      'author':    _authorController.text.trim().isEmpty
          ? 'Anonim' : _authorController.text.trim(),
      'category':  _selectedCategoryNotifier.value,
      'sibiLevel': _selectedSibiLevelNotifier.value,
    };

    Provider.of<UploadProvider>(context, listen: false)
        .startBackgroundProcessing(
      pdfFile:       _selectedPdfNotifier.value!,
      selectedPages: _selectedPagesNotifier.value,
      bookMetadata:  metadata,
      isPublic:      true,
      userId:        user.uid,
      coverImage:    _selectedImageNotifier.value,
    );

    showSystemPopup(
      context: context,
      type: PopupType.success,
      title: 'Memproses Bukumu! 🚀',
      message:
          'Buku sedang disiapkan di latar belakang. '
          'Setelah selesai, buku akan masuk antrian Juri Cilik untuk dinilai.',
      confirmText: 'Siap!',
      onConfirm: () => Navigator.pop(context),
    );
  }

  InputDecoration get _inputDeco => InputDecoration(
        filled: true,
        fillColor: GuruTheme.surfaceLow,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                const BorderSide(color: GuruTheme.primary, width: 2)),
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                const BorderSide(color: GuruTheme.errorRed, width: 1.5)),
        focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                const BorderSide(color: GuruTheme.errorRed, width: 2)),
      );

  @override
  Widget build(BuildContext context) {
    if (_isRoleChecking) {
      return Scaffold(
        backgroundColor: GuruTheme.surface,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: GuruTheme.primary),
              const SizedBox(height: 16),
              Text('Memeriksa akses...', style: GuruTheme.bodyMedium()),
            ],
          ),
        ),
      );
    }
    if (!_isRoleAuthorized) {
      return const Scaffold(body: SizedBox.shrink());
    }

    return Scaffold(
      backgroundColor: GuruTheme.surfaceLow,
      appBar: _buildAppBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Role verification banner (setelah load, banner jadi static info)
                _InfoBanner(
                  icon: Icons.shield_rounded,
                  text: 'Buku yang diupload akan masuk antrian Juri Cilik sebelum tayang.',
                ),
                const SizedBox(height: 16),

                // Step indicator
                _StepIndicator().animate().fadeIn(duration: 300.ms),
                const SizedBox(height: 20),

                // Form card
                _SectionCard(
                  title: 'INFORMASI BUKU',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _FieldLabel('Judul Cerita *'),
                      TextFormField(
                        controller: _titleController,
                        textInputAction: TextInputAction.next,
                        style: GuruTheme.bodyMedium(
                            color: GuruTheme.onSurface),
                        decoration: _inputDeco.copyWith(
                          hintText: 'Masukkan judul buku',
                          hintStyle: GuruTheme.bodyMedium(),
                          prefixIcon: const Icon(Icons.book_rounded,
                              color: GuruTheme.outline, size: 20),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Judul tidak boleh kosong'
                            : null,
                      ),
                      const SizedBox(height: 14),

                      _FieldLabel('Nama Pembuat (opsional)'),
                      TextFormField(
                        controller: _authorController,
                        textInputAction: TextInputAction.done,
                        style: GuruTheme.bodyMedium(
                            color: GuruTheme.onSurface),
                        decoration: _inputDeco.copyWith(
                          hintText: 'Nama penulis atau "Anonim"',
                          hintStyle: GuruTheme.bodyMedium(),
                          prefixIcon: const Icon(Icons.person_rounded,
                              color: GuruTheme.outline, size: 20),
                        ),
                      ),
                      const SizedBox(height: 14),

                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _FieldLabel('Jenis Cerita'),
                                ValueListenableBuilder<String>(
                                  valueListenable: _selectedCategoryNotifier,
                                  builder: (_, cat, __) =>
                                      DropdownButtonFormField<String>(
                                    isExpanded: true,
                                    value: cat,
                                    style: GuruTheme.bodyMedium(
                                        color: GuruTheme.onSurface),
                                    decoration: _inputDeco.copyWith(
                                      prefixIcon: const Icon(
                                          Icons.category_rounded,
                                          color: GuruTheme.outline,
                                          size: 20),
                                    ),
                                    items: _categoryItems,
                                    onChanged: (v) {
                                      if (v != null)
                                        _selectedCategoryNotifier.value = v;
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _FieldLabel('Level SIBI'),
                                ValueListenableBuilder<String>(
                                  valueListenable: _selectedSibiLevelNotifier,
                                  builder: (_, sibi, __) =>
                                      DropdownButtonFormField<String>(
                                    isExpanded: true,
                                    value: sibi,
                                    style: GuruTheme.bodyMedium(
                                        color: GuruTheme.onSurface),
                                    decoration: _inputDeco.copyWith(
                                      prefixIcon: const Icon(
                                          Icons.bar_chart_rounded,
                                          color: GuruTheme.outline,
                                          size: 20),
                                    ),
                                    items: _sibiLevelItems,
                                    onChanged: (v) {
                                      if (v != null)
                                        _selectedSibiLevelNotifier.value = v;
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ).animate(delay: 80.ms).fadeIn(duration: 350.ms),
                const SizedBox(height: 16),

                // Cover upload section
                _SectionCard(
                  title: 'FOTO SAMPUL BUKU',
                  child: ValueListenableBuilder<File?>(
                    valueListenable: _selectedImageNotifier,
                    builder: (_, selectedImage, __) =>
                        _UploadBox(
                      onTap: _pickImage,
                      icon: selectedImage != null
                          ? Icons.check_circle_rounded
                          : Icons.photo_camera_rounded,
                      iconColor: selectedImage != null
                          ? GuruTheme.successGreen
                          : GuruTheme.primary,
                      iconBg: selectedImage != null
                          ? GuruTheme.successGreenBg
                          : GuruTheme.primaryFixed,
                      title: selectedImage != null
                          ? selectedImage.path.split('/').last
                          : 'Foto Sampul Buku',
                      subtitle: selectedImage != null
                          ? 'Ketuk untuk mengganti'
                          : 'Ketuk untuk memilih dari galeri',
                      previewImage: selectedImage,
                    ),
                  ),
                ).animate(delay: 140.ms).fadeIn(duration: 350.ms),
                const SizedBox(height: 16),

                // PDF upload section
                _SectionCard(
                  title: 'FILE PDF BUKU',
                  child: ValueListenableBuilder<File?>(
                    valueListenable: _selectedPdfNotifier,
                    builder: (_, pdf, __) => ValueListenableBuilder<List<int>>(
                      valueListenable: _selectedPagesNotifier,
                      builder: (_, pages, __) => _UploadBox(
                        onTap: _pickPdf,
                        icon: pages.isNotEmpty
                            ? Icons.check_circle_rounded
                            : Icons.picture_as_pdf_rounded,
                        iconColor: pages.isNotEmpty
                            ? GuruTheme.successGreen
                            : GuruTheme.errorRed,
                        iconBg: pages.isNotEmpty
                            ? GuruTheme.successGreenBg
                            : GuruTheme.errorRedBg,
                        title: pdf != null
                            ? pdf.path.split('/').last
                            : 'File PDF Buku',
                        subtitle: pages.isNotEmpty
                            ? '✓ ${pages.length} halaman terpilih'
                            : 'Maks. 50MB · Ketuk untuk memilih',
                        subtitleColor: pages.isNotEmpty
                            ? GuruTheme.successGreen
                            : null,
                      ),
                    ),
                  ),
                ).animate(delay: 200.ms).fadeIn(duration: 350.ms),

                const SizedBox(height: 32),

                // Submit button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _triggerUpload,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: GuruTheme.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(
                      'Simpan ke Perpustakaan',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                  ),
                ).animate(delay: 260.ms).fadeIn(duration: 350.ms),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(61),
      child: Container(
        color: GuruTheme.surfaceLowest,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded,
                          color: GuruTheme.primary),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Text('Upload Buku Baru',
                        style: GuruTheme.titleLarge()),
                  ],
                ),
              ),
              Container(height: 3, color: GuruTheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoBanner({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: GuruTheme.primaryFixed,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: GuruTheme.primary, size: 18),
            const SizedBox(width: 10),
            Expanded(
                child: Text(text,
                    style: GuruTheme.bodySmall(color: GuruTheme.primary))),
          ],
        ),
      );
}

class _StepIndicator extends StatelessWidget {
  static const _steps = ['Info Buku', 'Review', 'Selesai'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(_steps.length * 2 - 1, (i) {
        if (i.isOdd) {
          return Expanded(
            child: Container(height: 2, color: GuruTheme.outlineVariant),
          );
        }
        final stepIndex = i ~/ 2;
        final active = stepIndex == 0;
        return Column(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: active ? GuruTheme.primary : GuruTheme.surfaceHigh,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text('${stepIndex + 1}',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: active
                          ? Colors.white
                          : GuruTheme.onSurfaceVariant,
                    )),
              ),
            ),
            const SizedBox(height: 4),
            Text(_steps[stepIndex],
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active
                      ? GuruTheme.primary
                      : GuruTheme.outlineVariant,
                  letterSpacing: 0.3,
                )),
          ],
        );
      }),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) => Container(
        decoration: GuruTheme.cardDecoration,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: GuruTheme.sectionHeader()),
            const SizedBox(height: 12),
            child,
          ],
        ),
      );
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child:
            Text(text, style: GuruTheme.labelMedium(color: GuruTheme.onSurface)),
      );
}

class _UploadBox extends StatelessWidget {
  final VoidCallback onTap;
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final Color? subtitleColor;
  final File? previewImage;

  const _UploadBox({
    required this.onTap,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    this.subtitleColor,
    this.previewImage,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          border: Border.all(
            color: GuruTheme.outlineVariant,
            width: 1.5,
            style: BorderStyle.solid,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            // Preview thumbnail untuk cover, icon untuk PDF
            if (previewImage != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(previewImage!,
                    width: 48, height: 64, fit: BoxFit.cover),
              )
            else
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                    color: iconBg, shape: BoxShape.circle),
                child: Icon(icon, color: iconColor, size: 24),
              ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GuruTheme.titleMedium()),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: GuruTheme.bodySmall(
                          color: subtitleColor ?? GuruTheme.outline)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}