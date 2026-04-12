// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';

class ParentalConsentDialog extends StatefulWidget {
  final VoidCallback onAgreed;

  const ParentalConsentDialog({super.key, required this.onAgreed});

  @override
  State<ParentalConsentDialog> createState() => _ParentalConsentDialogState();
}

class _ParentalConsentDialogState extends State<ParentalConsentDialog> {
  // 1. Buat Controller
  final ScrollController _scrollController = ScrollController();

  // Optimasi: Cache semua TextStyle agar tidak diinstansiasi ulang saat scroll/rebuild
  static final TextStyle _bodyStyle = GoogleFonts.poppins(
    fontSize: 14, 
    color: Colors.black87,
    height: 1.6,
  );

  static final TextStyle _buttonTextStyle = GoogleFonts.poppins(
    fontSize: 16,
    fontWeight: FontWeight.w600,
  );

  @override
  void dispose() {
    // 2. Wajib dispose controller untuk mencegah kebocoran memori
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: const Color(0xFFFFFBE6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        insetPadding: const EdgeInsets.all(20),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: size.height * 0.85,
            maxWidth: 400,
          ),
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Optimasi: Menggunakan const widget, bukan pemanggilan fungsi
              const _DialogHeader(),
              
              const SizedBox(height: 16),
              const Divider(thickness: 1, height: 1, color: Colors.orangeAccent),
              const SizedBox(height: 16),

              Expanded(
                // 3. Pasang Controller di Scrollbar
                child: Scrollbar(
                  controller: _scrollController, // <--- PENTING
                  thumbVisibility: true,
                  radius: const Radius.circular(8),
                  child: SingleChildScrollView(
                    // 4. Pasang Controller yang SAMA di SingleChildScrollView
                    controller: _scrollController, // <--- PENTING
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.only(right: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Selamat datang! Aplikasi dylearn dikembangkan sebagai bagian dari penelitian skripsi untuk membantu putra-putri Anda belajar membaca dengan metode yang menyenangkan.",
                          style: _bodyStyle,
                          textAlign: TextAlign.justify,
                        ),
                        const SizedBox(height: 20),
                        
                        const _ConsentSection(
                          icon: Icons.flag_rounded,
                          title: "Tujuan Aplikasi",
                          body: "Mengembangkan dan menguji efektivitas alat bantu baca berbasis OCR (Scan) dan TTS (Suara) khusus untuk anak disleksia.",
                        ),
                        
                        const _ConsentSection(
                          icon: Icons.admin_panel_settings_rounded,
                          title: "Data yang Dikumpulkan",
                          body: "• Hasil scan teks & riwayat baca anak.\n• Profil perkembangan membaca.\n• Jawaban kuesioner pengalaman pengguna.",
                        ),

                        const _ConsentSection(
                          icon: Icons.lock_rounded,
                          title: "Privasi & Keamanan",
                          body: "Data disimpan aman di server pribadi. Hanya Anda dan tim peneliti (untuk keperluan analisis skripsi) yang memiliki akses. Data tidak akan dipublikasikan secara personal.",
                        ),

                        const _ConsentSection(
                          icon: Icons.contact_support_rounded,
                          title: "Kontak Peneliti",
                          body: "Jika ada pertanyaan, hubungi:\nI Made Aris Danuarta (Undiksha)\n0851-5724-4627",
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange[800],
                    foregroundColor: Colors.white,
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('has_consented', true);
                    widget.onAgreed(); // Panggil callback dari widget
                  },
                  child: Text(
                    "Saya Mengerti & Setuju",
                    style: _buttonTextStyle,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Optimasi: Widget Statis untuk Header agar dapat dikonstruksi menggunakan 'const'
class _DialogHeader extends StatelessWidget {
  const _DialogHeader();

  static final TextStyle _titleStyle = GoogleFonts.poppins(
    fontSize: 20,
    fontWeight: FontWeight.bold,
    color: Colors.brown[800],
  );

  static final TextStyle _subtitleStyle = GoogleFonts.poppins(
    fontSize: 12,
    color: Colors.grey[600],
    fontStyle: FontStyle.italic,
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.verified_user_rounded, size: 40, color: Colors.orange[800]),
        ),
        const SizedBox(height: 12),
        Text(
          "Persetujuan Orang Tua",
          textAlign: TextAlign.center,
          style: _titleStyle,
        ),
        Text(
          "Parental Consent Form",
          style: _subtitleStyle,
        ),
      ],
    );
  }
}

class _ConsentSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _ConsentSection({
    required this.icon,
    required this.title,
    required this.body,
  });

  // Optimasi: Cache static styles untuk Section
  static final TextStyle _titleStyle = GoogleFonts.poppins(
    fontWeight: FontWeight.w600,
    fontSize: 15,
    color: Colors.brown[700],
  );

  static final TextStyle _bodyStyle = GoogleFonts.poppins(
    fontSize: 13,
    height: 1.5,
    color: Colors.black87,
  );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 20, color: Colors.orange[700]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: _titleStyle,
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: _bodyStyle,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}