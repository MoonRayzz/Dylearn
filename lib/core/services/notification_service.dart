// ignore_for_file: depend_on_referenced_packages

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';

class NotificationService {
  // ===============================================================
  // SINGLETON (Optimasi RAM)
  // ===============================================================
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() => _instance;

  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  // ===============================================================
  // INIT SYSTEM + TIMEZONE
  // ===============================================================
  Future<void> init() async {
    if (_isInitialized) return;

    tz.initializeTimeZones();
    try {
      final TimezoneInfo tzInfo = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(tzInfo.identifier));
    } catch (e) {
      debugPrint("Timezone error (fallback ke UTC): $e");
    }

    // Menggunakan icon custom (pastikan ic_notification ada di folder drawable)
    const AndroidInitializationSettings initSettingsAndroid =
        AndroidInitializationSettings('@drawable/ic_notification');

    const DarwinInitializationSettings initSettingsDarwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const InitializationSettings initSettings = InitializationSettings(
      android: initSettingsAndroid,
      iOS: initSettingsDarwin,
      macOS: initSettingsDarwin,
    );

    await _notificationsPlugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        debugPrint("Notifikasi ditekan: ${response.payload}");
      },
    );

    _isInitialized = true;
  }

  // ===============================================================
  // REQUEST PERMISSION (Android 13+ & iOS)
  // ===============================================================
  Future<void> requestPermission() async {
    if (Platform.isAndroid) {
      final androidPlugin = _notificationsPlugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

      await androidPlugin?.requestNotificationsPermission();
    }

    if (Platform.isIOS) {
      final iosPlugin = _notificationsPlugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();

      await iosPlugin?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
    }
  }

  // ===============================================================
  // FOREGROUND UPLOAD PROGRESS (TRIK ANIMASI EMOJI)
  // ===============================================================
  Future<void> showUploadProgress(int progress, String message) async {
    
    // [TRIK 1] Animasi Jam Pasir yang seolah-olah berdetak/berputar
    List<String> loadingEmojis = ['⏳', '⌛'];
    String activeTick = loadingEmojis[progress % 2]; 

    // [TRIK 2] Storytelling berdasarkan Persentase Progress
    String dynamicTitle;
    if (progress < 15) {
      dynamicTitle = '$activeTick Siap-siap meracik buku... $progress%';
    } else if (progress < 40) {
      dynamicTitle = '🔍 Membaca huruf perlahan... $progress%';
    } else if (progress < 70) {
      dynamicTitle = '🤖 Robot sedang bekerja... $progress%';
    } else if (progress < 90) {
      dynamicTitle = '🚀 Meluncur menyimpan buku... $progress%';
    } else {
      dynamicTitle = '✨ Sedikit lagi rapi... $progress%';
    }

    final androidDetails = AndroidNotificationDetails(
      'upload_book_channel',
      'Upload Buku',
      channelDescription: 'Progres pemrosesan buku di latar belakang',
      icon: 'ic_notification',
      importance: Importance.low, // Agar tidak bunyi terus saat update
      priority: Priority.low,
      showProgress: true,
      maxProgress: 100,
      progress: progress,
      ongoing: true, // Tidak bisa di-swipe
      onlyAlertOnce: true, // Hanya getar di awal, selanjutnya update secara "silent"
      color: const Color(0xFFFF9F1C),
    );

    if (Platform.isAndroid) {
      final androidPlugin = _notificationsPlugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

      await androidPlugin?.startForegroundService(
        id: 888,
        title: dynamicTitle,
        body: message, // Text detail dari upload_provider (contoh: "Hal 1 Selesai")
        notificationDetails: androidDetails,
      );
    } else {
      await _notificationsPlugin.show(
        id: 888,
        title: dynamicTitle,
        body: message,
        notificationDetails: NotificationDetails(android: androidDetails),
      );
    }
  }

  // ===============================================================
  // STOP FOREGROUND + SHOW RESULT
  // ===============================================================
  Future<void> stopUploadProgressAndShowResult(
    String title,
    String message, {
    bool isError = false,
  }) async {
    if (Platform.isAndroid) {
      final androidPlugin = _notificationsPlugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

      await androidPlugin?.stopForegroundService();
    }

    final androidDetails = AndroidNotificationDetails(
      'upload_book_channel',
      'Upload Buku',
      channelDescription: 'Hasil proses upload buku',
      icon: 'ic_notification',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      color: isError ? Colors.red : const Color(0xFFFF9F1C),
    );

    await _notificationsPlugin.show(
      id: 888,
      title: title,
      body: message,
      notificationDetails: NotificationDetails(
        android: androidDetails,
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }

  // ===============================================================
  // SCHEDULE READING REMINDER (24 JAM)
  // ===============================================================
  Future<void> scheduleReadingReminder(String bookTitle) async {
    await _notificationsPlugin.cancel(id: 101);

    final scheduledDate = tz.TZDateTime.now(tz.local).add(const Duration(hours: 24));

    const androidDetails = AndroidNotificationDetails(
      'reminder_channel',
      'Pengingat Membaca',
      channelDescription: 'Pengingat cerita yang belum selesai',
      icon: 'ic_notification',
      importance: Importance.high,
      priority: Priority.high,
      color: Color(0xFF2EC4B6),
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: const DarwinNotificationDetails(),
    );

    await _notificationsPlugin.zonedSchedule(
      id: 101,
      title: 'Halo Teman! 🌟',
      body: 'Cerita "$bookTitle" belum selesai lho. Yuk kita lihat kelanjutannya!',
      scheduledDate: scheduledDate,
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  // ===============================================================
  // ACHIEVEMENT NOTIFICATION
  // ===============================================================
  Future<void> showAchievementNotification(String title, String body) async {
    const androidDetails = AndroidNotificationDetails(
      'achievement_channel',
      'Pencapaian',
      channelDescription: 'Apresiasi aktivitas membaca anak',
      icon: 'ic_notification',
      importance: Importance.high,
      priority: Priority.high,
      color: Color(0xFFFF9F1C),
    );

    await _notificationsPlugin.show(
      id: 202,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: androidDetails,
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  // ===============================================================
  // PANGGILAN JURI CILIK
  // ===============================================================
  Future<void> showJuriCilikNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'juri_cilik_channel',
      'Juri Cilik',
      channelDescription: 'Panggilan untuk menilai cerita teman',
      icon: 'ic_notification',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      color: Color(0xFFFF9F1C),
    );

    await _notificationsPlugin.show(
      id: 303,
      title: 'Ada Cerita Baru! 🏆',
      body: 'Yuk jadi Juri Cilik dan berikan bintangmu untuk cerita teman-teman!',
      notificationDetails: const NotificationDetails(
        android: androidDetails,
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  // ===============================================================
  // STATUS BUKU (DITERIMA / DITOLAK ADMIN ATAU SISTEM VOTE)
  // ===============================================================
  Future<void> showBookStatusNotification(String bookTitle, bool isAccepted) async {
    final int dynamicId = DateTime.now().millisecond % 10000; 

    final androidDetails = AndroidNotificationDetails(
      'book_status_channel',
      'Status Buku',
      channelDescription: 'Pemberitahuan apakah buku disetujui atau ditolak',
      icon: 'ic_notification',
      importance: Importance.high,
      priority: Priority.high,
      color: isAccepted ? const Color(0xFF2EC4B6) : Colors.red,
    );

    await _notificationsPlugin.show(
      id: dynamicId,
      title: isAccepted ? 'Hore! Buku Diterima 🎉' : 'Yah, Buku Dikembalikan 😔',
      body: isAccepted 
          ? 'Buku "$bookTitle" sudah lolos review dan sekarang bisa dibaca teman-teman!' 
          : 'Buku "$bookTitle" belum memenuhi kriteria perpustakaan. Tetap semangat ya!',
      notificationDetails: NotificationDetails(
        android: androidDetails,
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }

  // ===============================================================
  // VOTE DARI TEMAN
  // ===============================================================
  Future<void> showVoteReceivedNotification(String bookTitle, bool isLike) async {
    final int dynamicId = (DateTime.now().millisecond + 1) % 10000;

    const androidDetails = AndroidNotificationDetails(
      'vote_received_channel',
      'Vote Teman',
      channelDescription: 'Pemberitahuan saat buku mendapat penilaian',
      icon: 'ic_notification',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      color: Color(0xFFFF9F1C),
    );

    await _notificationsPlugin.show(
      id: dynamicId,
      title: isLike ? 'Wah, Ada yang Suka Bukumu! 🌟' : 'Ada Penilaian Baru 🤔',
      body: isLike 
          ? 'Seseorang baru saja memberikan bintang untuk buku "$bookTitle"!' 
          : 'Seseorang telah menilai buku "$bookTitle". Jadikan motivasi untuk berkarya!',
      notificationDetails: const NotificationDetails(
        android: androidDetails,
        iOS: DarwinNotificationDetails(),
      ),
    );
  }
}