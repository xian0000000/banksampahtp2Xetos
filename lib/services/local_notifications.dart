import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Wrapper tipis di atas flutter_local_notifications supaya init & show
/// notifikasi transaksi dipakai dari satu tempat saja (dipanggil dari
/// main() dan dari TransactionNotifier).
///
/// flutter_local_notifications tidak mendukung web, jadi di web fungsi di
/// sini sengaja no-op. Semua error saat init/show juga sengaja ditelan
/// (try/catch) supaya kegagalan notifikasi (mis. izin ditolak user, atau
/// platform channel belum ke-setup di project Android/iOS) tidak sampai
/// bikin dashboard nasabah crash — notifikasi itu fitur tambahan, bukan
/// fitur inti aplikasi.
class LocalNotifications {
  LocalNotifications._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  static const String _channelId = 'transaksi_bank_sampah';
  static const String _channelName = 'Transaksi Bank Sampah';
  static const String _channelDescription =
      'Notifikasi setiap kali ada transaksi setor atau tarik saldo baru.';

  /// Panggil sekali di main() sebelum runApp(). Aman dipanggil berkali-kali
  /// (no-op kalau sudah pernah berhasil init).
  static Future<void> init() async {
    if (kIsWeb || _initialized) return;

    try {
      const androidInit =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const initSettings = InitializationSettings(
        android: androidInit,
        iOS: iosInit,
        macOS: iosInit,
      );

      await _plugin.initialize(initSettings);

      // Android 13+ (API 33) mewajibkan izin notifikasi diminta secara
      // eksplisit saat runtime, bukan cuma lewat AndroidManifest.
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();

      await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);

      const androidChannel = AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.high,
      );

      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(androidChannel);

      _initialized = true;
    } catch (_) {
      // Gagal inisialisasi (mis. platform belum lengkap di-setup) —
      // anggap saja notifikasi tidak tersedia, jangan sampai app gagal
      // start gara-gara ini.
    }
  }

  /// Tampilkan satu notifikasi lokal. `id` sebaiknya beda-beda per
  /// notifikasi supaya tidak saling menimpa di tray notifikasi.
  static Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {
    if (kIsWeb || !_initialized) return;

    try {
      const androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.high,
        priority: Priority.high,
      );
      const iosDetails = DarwinNotificationDetails();
      const details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
        macOS: iosDetails,
      );

      await _plugin.show(id, title, body, details);
    } catch (_) {
      // Sama seperti init() — diamkan biar gak mengganggu alur utama app.
    }
  }
}
