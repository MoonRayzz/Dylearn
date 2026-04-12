// ignore_for_file: deprecated_member_use, unused_local_variable

import 'dart:async';
import 'package:flutter/material.dart';

class QuoteWidget extends StatefulWidget {
  const QuoteWidget({super.key});

  @override
  State<QuoteWidget> createState() => _QuoteWidgetState();
}

class _QuoteWidgetState extends State<QuoteWidget> {
  // OPTIMASI: Dijadikan static const agar hanya dialokasikan 1x di memori
  static const List<String> _quotes = [
    "Setiap kata adalah petualangan baru. Ayo jelajahi! 🚀",
    "Membaca membuka jendela dunia, satu kata demi satu kata. 🌍",
    "Kamu hebat! Setiap huruf yang kamu kenali adalah kemenangan. 🏆",
    "Jangan takut salah, kita belajar bersama di sini. 💪",
    "Suaramu punya kekuatan untuk menghidupkan cerita. 🎙️",
    "Dengan membaca, kamu bisa menjadi apa saja yang kamu mau! ✨",
  ];

  // OPTIMASI: Menggunakan ValueNotifier untuk mencegah rebuild seluruh kotak
  final ValueNotifier<int> _currentIndexNotifier = ValueNotifier<int>(0);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (mounted) {
        // OPTIMASI: Hanya memperbarui nilai notifier, bukan memanggil setState
        _currentIndexNotifier.value = (_currentIndexNotifier.value + 1) % _quotes.length;
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _currentIndexNotifier.dispose(); // Wajib dispose notifier untuk mencegah memory leak
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // OPTIMASI: Menggunakan const dan menghapus primaryColor yang tidak dipakai
    const Color backgroundColor = Color(0xFFFFF7ED);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.orange.shade200, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Indikator visual/icon agar lebih menarik bagi anak-anak
          Image.asset('assets/images/UNDIKSHA.png', width: 90, height: 90), // <-- BAGIAN YANG DIREVISI
          const SizedBox(width: 14),
          
          Expanded(
            child: ValueListenableBuilder<int>(
              valueListenable: _currentIndexNotifier,
              builder: (context, currentIndex, child) {
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 600),
                  // Animasi transisi slide up + fade agar lebih modern
                  transitionBuilder: (Widget child, Animation<double> animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0.0, 0.2),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: Text(
                    _quotes[currentIndex],
                    key: ValueKey<int>(currentIndex),
                    textAlign: TextAlign.start,
                    // FONT DINAMIS
                    style: TextStyle(
                      fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                      height: 1.3,
                      letterSpacing: 0.5,
                    ),
                  ),
                );
              }
            ),
          ),
        ],
      ),
    );
  }
}