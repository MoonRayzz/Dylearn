// ignore_for_file: use_build_context_synchronously, deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../config/guru_theme.dart';
import '../../../core/services/auth_service.dart';

class AddStudentScreen extends StatefulWidget {
  const AddStudentScreen({super.key});

  @override
  State<AddStudentScreen> createState() => _AddStudentScreenState();
}

class _AddStudentScreenState extends State<AddStudentScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final AuthService _authService = AuthService();
  late final TextEditingController _nameController;
  late final TextEditingController _ageController;

  String _selectedGender   = 'L';
  String _selectedGrade    = 'SD 1';
  String _selectedDyslexia = 'Belum Tahu';

  final ValueNotifier<bool> _isLoadingNotifier = ValueNotifier<bool>(false);

  static const List<String> _gradeOptions   = ['SD 1','SD 2','SD 3','SD 4','SD 5','SD 6'];
  static const List<String> _dyslexiaOptions = ['Belum Tahu','Ringan','Sedang','Berat'];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _ageController  = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _isLoadingNotifier.dispose();
    super.dispose();
  }

  // ── Logic: simpan murid via AuthService ────────────────────────────────────
  Future<void> _saveStudent() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    _isLoadingNotifier.value = true;
    try {
      final user = _authService.currentUser;
      if (user == null) throw Exception('Sesi guru tidak valid.');
      await _authService.createManagedStudent(
        teacherUid:   user.uid,
        name:         _nameController.text.trim(),
        age:          int.tryParse(_ageController.text.trim()) ?? 0,
        gender:       _selectedGender,
        grade:        _selectedGrade,
        dyslexiaType: _selectedDyslexia,
      );
      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Murid berhasil ditambahkan!'),
          backgroundColor: GuruTheme.successGreen,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Gagal: ${e.toString().replaceAll('Exception:', '')}'),
          backgroundColor: GuruTheme.errorRed,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) _isLoadingNotifier.value = false;
    }
  }

  // Shared input decoration
  InputDecoration get _inputDecoration => InputDecoration(
        filled: true,
        fillColor: GuruTheme.surfaceLow,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: GuruTheme.primary, width: 2)),
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: GuruTheme.errorRed, width: 1.5)),
        focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: GuruTheme.errorRed, width: 2)),
      );

  @override
  Widget build(BuildContext context) {
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
                // Info banner
                _InfoBanner(),
                const SizedBox(height: 20),

                // Card 1: Identitas
                _FormCard(
                  title: 'IDENTITAS MURID',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _FieldLabel('Nama Lengkap *'),
                      TextFormField(
                        controller: _nameController,
                        textInputAction: TextInputAction.next,
                        style: GuruTheme.bodyMedium(color: GuruTheme.onSurface),
                        decoration: _inputDecoration.copyWith(
                          hintText: 'Contoh: Budi Santoso',
                          hintStyle: GuruTheme.bodyMedium(),
                          prefixIcon: const Icon(Icons.person_outline_rounded,
                              color: GuruTheme.outline, size: 20),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Nama tidak boleh kosong'
                            : null,
                      ),
                      const SizedBox(height: 16),

                      _FieldLabel('Umur (Tahun) *'),
                      TextFormField(
                        controller: _ageController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        textInputAction: TextInputAction.done,
                        style: GuruTheme.bodyMedium(color: GuruTheme.onSurface),
                        decoration: _inputDecoration.copyWith(
                          hintText: 'Contoh: 8',
                          hintStyle: GuruTheme.bodyMedium(),
                          prefixIcon: const Icon(Icons.cake_outlined,
                              color: GuruTheme.outline, size: 20),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Umur tidak boleh kosong';
                          if (int.tryParse(v) == null || int.parse(v) <= 0) {
                            return 'Masukkan angka yang benar';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      _FieldLabel('Jenis Kelamin'),
                      _GenderSelector(
                        selected: _selectedGender,
                        onChanged: (v) => setState(() => _selectedGender = v),
                      ),
                    ],
                  ),
                ).animate().fadeIn(duration: 350.ms),

                const SizedBox(height: 16),

                // Card 2: Informasi Belajar
                _FormCard(
                  title: 'INFORMASI BELAJAR',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _FieldLabel('Kelas'),
                      _ChipGrid(
                        options: _gradeOptions,
                        selected: _selectedGrade,
                        crossAxisCount: 3,
                        onChanged: (v) => setState(() => _selectedGrade = v),
                      ),
                      const SizedBox(height: 16),

                      _FieldLabel('Tipe Disleksia'),
                      _ChipGrid(
                        options: _dyslexiaOptions,
                        selected: _selectedDyslexia,
                        crossAxisCount: 2,
                        onChanged: (v) => setState(() => _selectedDyslexia = v),
                      ),
                    ],
                  ),
                ).animate(delay: 80.ms).fadeIn(duration: 350.ms),

                const SizedBox(height: 28),

                // Submit button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ValueListenableBuilder<bool>(
                    valueListenable: _isLoadingNotifier,
                    builder: (context, isLoading, _) => ElevatedButton(
                      onPressed: isLoading ? null : _saveStudent,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: GuruTheme.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2.5))
                          : Text(
                              'Simpan Data Murid',
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 15, fontWeight: FontWeight.w700),
                            ),
                    ),
                  ),
                ).animate(delay: 160.ms).fadeIn(duration: 350.ms),

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
                    Text('Tambah Murid Baru',
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
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _InfoBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: GuruTheme.primaryFixed,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded,
              color: GuruTheme.primary, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Data murid ini digunakan untuk sesi pendampingan. Kode sinkronisasi dapat dibuat setelahnya.',
              style: GuruTheme.bodySmall(color: GuruTheme.primary),
            ),
          ),
        ],
      ),
    );
  }
}

class _FormCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _FormCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: GuruTheme.cardDecoration,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: GuruTheme.sectionHeader()),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: GuruTheme.labelMedium(color: GuruTheme.onSurface)),
      );
}

// Gender selector: dua tombol sejajar
class _GenderSelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const _GenderSelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: GuruTheme.surfaceMid,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _GenderOption(
              label: 'Laki-laki',
              value: 'L',
              selected: selected,
              onTap: onChanged),
          _GenderOption(
              label: 'Perempuan',
              value: 'P',
              selected: selected,
              onTap: onChanged),
        ],
      ),
    );
  }
}

class _GenderOption extends StatelessWidget {
  final String label;
  final String value;
  final String selected;
  final ValueChanged<String> onTap;

  const _GenderOption({
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool active = selected == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: active ? GuruTheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: active ? GuruTheme.cardShadow : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: active ? Colors.white : GuruTheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

// Chip grid untuk grade dan dyslexia
class _ChipGrid extends StatelessWidget {
  final List<String> options;
  final String selected;
  final int crossAxisCount;
  final ValueChanged<String> onChanged;

  const _ChipGrid({
    required this.options,
    required this.selected,
    required this.crossAxisCount,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((opt) {
        final bool active = selected == opt;
        return GestureDetector(
          onTap: () => onChanged(opt),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: active ? GuruTheme.primary : GuruTheme.surfaceLowest,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: active ? GuruTheme.primary : GuruTheme.outlineVariant,
                width: active ? 2 : 1,
              ),
              boxShadow: active ? GuruTheme.cardShadow : null,
            ),
            child: Text(
              opt,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? Colors.white : GuruTheme.onSurfaceVariant,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}