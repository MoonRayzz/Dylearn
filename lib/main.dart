// ignore_for_file: deprecated_member_use

import 'package:flutter/gestures.dart'; 
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:showcaseview/showcaseview.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'firebase_options.dart';
import 'shared/providers/settings_provider.dart';
import 'shared/providers/upload_provider.dart'; 
import 'config/app_theme.dart'; 
import 'features/auth/auth_wrapper.dart'; 
import 'core/services/notification_service.dart'; 

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  GestureBinding.instance.resamplingEnabled = true;
  
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));

  try {
    await Future.wait([
      Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform),
      initializeDateFormatting('id_ID', null),
      initializeDateFormatting('en_US', null),
      NotificationService().init(), 
      dotenv.load(fileName: ".env").catchError((e) {
        debugPrint("⚠️ Peringatan: File .env tidak ditemukan atau gagal dimuat: $e");
        return; 
      }),
    ]);
  } catch (e) {
    debugPrint("Initialization Error: $e");
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => UploadProvider()), 
      ],
      child: const DyLearnApp(),
    ),
  );
}

class DyLearnApp extends StatelessWidget {
  const DyLearnApp({super.key});

  static Widget _authWrapperBuilder(BuildContext context) => const AuthWrapper();

  @override
  Widget build(BuildContext context) {
    // ════════════════════════════════════════════════════════════════
    // FIX FONT LAG:
    // fontFamily TIDAK di-watch di sini supaya MaterialApp tidak rebuild
    // setiap kali font diganti. getLightTheme/getDarkTheme dipanggil SEKALI
    // saja tanpa fontFamily — font diterapkan di dalam builder() di bawah.
    // ════════════════════════════════════════════════════════════════
    final themeMode = context.select<SettingsProvider, ThemeMode>((p) => p.themeMode);
    final locale = context.select<SettingsProvider, Locale?>((p) => p.locale);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Dylearn',
      
      // Tidak lagi menerima fontFamily — tema stabil, tidak rebuild saat font diganti
      theme: AppTheme.getLightTheme(null),
      darkTheme: AppTheme.getDarkTheme(null),
      themeMode: themeMode,
      
      locale: locale,
      
      builder: (context, child) {
        if (child == null) return const SizedBox.shrink();
        
        // ════════════════════════════════════════════════════════════════
        // fontFamily dan textScaleFactor dibaca di sini.
        // Perubahan hanya rebuild builder ini — bukan MaterialApp/Navigator.
        // Theme.copyWith() menerapkan font ke seluruh subtree tanpa
        // menyentuh widget tree di atas (AppBar, Scaffold, dst).
        // ════════════════════════════════════════════════════════════════
        final settings = context.watch<SettingsProvider>();
        final textScaleFactor = settings.textScaleFactor;
        final fontFamily = settings.fontFamily;
        final mediaQueryData = MediaQuery.of(context);

        return Theme(
          data: Theme.of(context).copyWith(
            textTheme: Theme.of(context).textTheme.apply(
              fontFamily: fontFamily,
            ),
          ),
          child: MediaQuery(
            data: mediaQueryData.copyWith(
              textScaler: TextScaler.linear(textScaleFactor.clamp(0.8, 1.5)), 
            ),
            // ════════════════════════════════════════════════════════════════
            // FONT PRE-WARMER v2:
            //
            // BUG v1: color: Colors.transparent → Flutter skip paint → glyph
            //         cache tidak pernah terbentuk → lag tetap ada.
            //
            // FIX v2:
            //   1. Gunakan Opacity(opacity: 0) sebagai wrapper, bukan warna
            //      transparent. Opacity widget tetap trigger layout + paint
            //      pass sehingga glyph benar-benar di-cache oleh Skia/HarfBuzz.
            //   2. Render di beberapa ukuran font (12, 16, 20, 28) karena
            //      TTF cache glyph per-size — render 1 ukuran saja tidak cukup.
            //   3. Semua pre-warmer di-wrap RepaintBoundary agar tidak ikut
            //      repaint saat konten utama berubah.
            // ════════════════════════════════════════════════════════════════
            child: Stack(
              children: [
                child, // Konten utama aplikasi
                // FONT PRE-WARMER v2.1
                Positioned(
                  left: -9999,
                  top: -9999,
                  child: RepaintBoundary(
                    child: Opacity(
                      opacity: 0.01, // Hindari 0.0 absolut agar engine tidak mengabaikannya
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Looping untuk memanaskan ukuran normal dan BOLD
                          for (var size in [12.0, 16.0, 20.0, 28.0]) ...[
                            Text(
                              'AaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVvWwXxYyZz0123456789',
                              style: TextStyle(fontFamily: fontFamily, fontSize: size, fontWeight: FontWeight.normal),
                            ),
                            Text( // Panaskan juga versi BOLD
                              'AaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVvWwXxYyZz0123456789',
                              style: TextStyle(fontFamily: fontFamily, fontSize: size, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
      
      home: ShowCaseWidget(
        builder: _authWrapperBuilder,
      ),
    );
  }
}